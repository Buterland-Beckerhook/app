defmodule BbhWeb.Api.MCPControllerTest do
  use BbhWeb.ConnCase, async: true

  import Bbh.AccountsFixtures
  import Bbh.ContentFixtures

  alias Bbh.ApiTokens
  alias Bbh.Content

  setup do
    user = admin_user_fixture()
    {:ok, plaintext, token} = ApiTokens.create_pat(user, "test", ["mcp:read", "mcp:write"])
    %{user: user, token: token, bearer: plaintext}
  end

  ## Helpers

  defp rpc(conn, bearer, payload) do
    conn
    |> put_req_header("content-type", "application/json")
    |> put_req_header("authorization", "Bearer #{bearer}")
    |> post(~p"/mcp", Jason.encode!(payload))
  end

  defp tool_call(conn, bearer, name, arguments) do
    rpc(conn, bearer, %{
      jsonrpc: "2.0",
      id: 1,
      method: "tools/call",
      params: %{name: name, arguments: arguments}
    })
  end

  # Unwraps the JSON a successful tool call carries in its text content.
  defp tool_data(conn) do
    %{"result" => %{"isError" => false, "content" => [%{"text" => text}]}} =
      json_response(conn, 200)

    Jason.decode!(text)
  end

  defp tool_error(conn) do
    %{"result" => %{"isError" => true, "content" => [%{"text" => text}]}} =
      json_response(conn, 200)

    text
  end

  ## Authentication

  describe "authentication" do
    test "rejects a request with no token and points at the metadata", %{conn: conn} do
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post(~p"/mcp", Jason.encode!(%{jsonrpc: "2.0", id: 1, method: "ping"}))

      assert json_response(conn, 401)["error"] == "invalid_token"

      assert [challenge] = get_resp_header(conn, "www-authenticate")
      assert challenge =~ ~s(resource_metadata=")
      assert challenge =~ "/.well-known/oauth-protected-resource/mcp"
    end

    test "rejects a garbage token", %{conn: conn} do
      conn = rpc(conn, "not-a-token", %{jsonrpc: "2.0", id: 1, method: "ping"})
      assert json_response(conn, 401)
    end

    test "rejects a revoked token", %{conn: conn, bearer: bearer, token: token} do
      {:ok, _} = ApiTokens.revoke(token)

      conn = rpc(conn, bearer, %{jsonrpc: "2.0", id: 1, method: "ping"})
      assert json_response(conn, 401)
    end

    test "rejects an expired token", %{conn: conn, bearer: bearer, token: token} do
      past = DateTime.utc_now() |> DateTime.add(-1, :day) |> DateTime.truncate(:second)
      token |> Ecto.Changeset.change(expires_at: past) |> Bbh.Repo.update!()

      conn = rpc(conn, bearer, %{jsonrpc: "2.0", id: 1, method: "ping"})
      assert json_response(conn, 401)
    end

    test "records that the token was used", %{conn: conn, bearer: bearer, token: token} do
      rpc(conn, bearer, %{jsonrpc: "2.0", id: 1, method: "ping"})

      assert Bbh.Repo.get!(Bbh.ApiTokens.ApiToken, token.id).last_used_at
    end
  end

  ## Transport

  describe "transport" do
    test "answers a request with a single JSON object", %{conn: conn, bearer: bearer} do
      conn = rpc(conn, bearer, %{jsonrpc: "2.0", id: 7, method: "ping"})

      assert ["application/json" <> _] = get_resp_header(conn, "content-type")
      assert %{"jsonrpc" => "2.0", "id" => 7, "result" => %{}} = json_response(conn, 200)
    end

    test "answers a notification with 202 and no body", %{conn: conn, bearer: bearer} do
      conn = rpc(conn, bearer, %{jsonrpc: "2.0", method: "notifications/initialized"})

      assert response(conn, 202) == ""
    end

    test "rejects an unsupported protocol version with 400", %{conn: conn, bearer: bearer} do
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> put_req_header("authorization", "Bearer #{bearer}")
        |> put_req_header("mcp-protocol-version", "1999-01-01")
        |> post(~p"/mcp", Jason.encode!(%{jsonrpc: "2.0", id: 1, method: "ping"}))

      assert json_response(conn, 400)["error"]["message"] =~ "Unsupported MCP-Protocol-Version"
    end

    test "accepts a supported protocol version header", %{conn: conn, bearer: bearer} do
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> put_req_header("authorization", "Bearer #{bearer}")
        |> put_req_header("mcp-protocol-version", "2025-06-18")
        |> post(~p"/mcp", Jason.encode!(%{jsonrpc: "2.0", id: 1, method: "ping"}))

      assert json_response(conn, 200)
    end

    test "rejects a batch", %{conn: conn, bearer: bearer} do
      conn = rpc(conn, bearer, [%{jsonrpc: "2.0", id: 1, method: "ping"}])

      assert json_response(conn, 400)["error"]["message"] =~ "Batch"
    end

    test "GET answers 405 — this server opens no stream", %{conn: conn, bearer: bearer} do
      result = conn |> put_req_header("authorization", "Bearer #{bearer}") |> get(~p"/mcp")

      assert json_response(result, 405)
      assert ["POST, OPTIONS"] = get_resp_header(result, "allow")
    end

    test "DELETE answers 405 — there is no session to end", %{conn: conn, bearer: bearer} do
      result = conn |> put_req_header("authorization", "Bearer #{bearer}") |> delete(~p"/mcp")

      assert json_response(result, 405)
      assert ["POST, OPTIONS"] = get_resp_header(result, "allow")
    end

    test "stamps CORS headers on an ordinary response too, not just the preflight", %{
      conn: conn,
      bearer: bearer
    } do
      conn = rpc(conn, bearer, %{jsonrpc: "2.0", id: 1, method: "ping"})

      assert ["*"] = get_resp_header(conn, "access-control-allow-origin")
      assert [exposed] = get_resp_header(conn, "access-control-expose-headers")
      # Without this a browser client cannot read the challenge that tells it how to authorize.
      assert exposed =~ "www-authenticate"
    end

    test "answers a CORS preflight without requiring a token", %{conn: conn} do
      conn = options(conn, ~p"/mcp")

      assert response(conn, 204)
      assert ["*"] = get_resp_header(conn, "access-control-allow-origin")
      assert [allowed] = get_resp_header(conn, "access-control-allow-headers")
      assert allowed =~ "authorization"
    end
  end

  ## Tools

  describe "article tools" do
    test "creates a draft, adds a block and sets an image", %{conn: conn, bearer: bearer} do
      article =
        conn
        |> tool_call(bearer, "create_article", %{
          "title" => "Schützenfest 2026",
          "author" => "Claude"
        })
        |> tool_data()

      # Draft by default, and the slug is transliterated rather than mangled.
      assert article["status"] == "draft"
      assert article["slug"] == "schuetzenfest-2026"
      assert article["year"] == Date.utc_today().year

      block =
        conn
        |> tool_call(bearer, "add_article_block", %{
          "article_id" => article["id"],
          "type" => "richtext",
          "body" => "Erster Absatz.\n\nZweiter Absatz."
        })
        |> tool_data()

      # Markdown paragraphs must survive as paragraphs: `Bbh.Html.sanitize/1` merges
      # adjacent <p> into one, so the body is prepared with `to_editor/1` first.
      assert block["type"] == "richtext"
      assert block["body"] == "<p>Erster Absatz.</p><p>Zweiter Absatz.</p>"

      upload = upload_fixture()

      updated =
        conn
        |> tool_call(bearer, "set_article_image", %{
          "article_id" => article["id"],
          "media_id" => upload.id
        })
        |> tool_data()

      assert updated["image"]["id"] == upload.id
      assert updated["image"]["url"] =~ "/media/"
    end

    test "sanitizes HTML the model supplies", %{conn: conn, bearer: bearer} do
      article = conn |> tool_call(bearer, "create_article", %{"title" => "X"}) |> tool_data()

      block =
        conn
        |> tool_call(bearer, "add_article_block", %{
          "article_id" => article["id"],
          "type" => "richtext",
          "format" => "html",
          "body" => "<p>ok<script>alert(1)</script><img src=x onerror=\"evil()\"></p>"
        })
        |> tool_data()

      refute block["body"] =~ "script"
      refute block["body"] =~ "onerror"
      assert block["body"] =~ "ok"
    end

    test "reorders blocks", %{conn: conn, bearer: bearer} do
      article = conn |> tool_call(bearer, "create_article", %{"title" => "X"}) |> tool_data()

      for body <- ["eins", "zwei"] do
        tool_call(conn, bearer, "add_article_block", %{
          "article_id" => article["id"],
          "type" => "richtext",
          "body" => body
        })
      end

      second =
        conn
        |> tool_call(bearer, "get_article", %{"article_id" => article["id"]})
        |> tool_data()
        |> Map.fetch!("blocks")
        |> Enum.at(1)

      moved =
        conn
        |> tool_call(bearer, "move_article_block", %{
          "block_id" => second["id"],
          "direction" => "up"
        })
        |> tool_data()

      assert [%{"id" => first_id}, _] = moved["blocks"]
      assert first_id == second["id"]
    end

    test "a single newline stays one paragraph, a blank line starts a new one", %{
      conn: conn,
      bearer: bearer
    } do
      # Standard Markdown semantics, pinned deliberately: a soft break continues the
      # paragraph, a blank line breaks it. The companion hard-break case is covered above.
      article = conn |> tool_call(bearer, "create_article", %{"title" => "X"}) |> tool_data()

      block =
        conn
        |> tool_call(bearer, "add_article_block", %{
          "article_id" => article["id"],
          "type" => "richtext",
          "body" => "Erste Zeile.\nZweite Zeile."
        })
        |> tool_data()

      assert block["body"] =~ ~r{\A<p>Erste Zeile\.\s+Zweite Zeile\.</p>\z}
      refute block["body"] =~ "</p><p>"
    end

    test "moving a block at the list edge is a no-op, not an error", %{
      conn: conn,
      bearer: bearer
    } do
      article = conn |> tool_call(bearer, "create_article", %{"title" => "X"}) |> tool_data()

      for body <- ["eins", "zwei"] do
        tool_call(conn, bearer, "add_article_block", %{
          "article_id" => article["id"],
          "type" => "richtext",
          "body" => body
        })
      end

      [first, last] =
        conn
        |> tool_call(bearer, "get_article", %{"article_id" => article["id"]})
        |> tool_data()
        |> Map.fetch!("blocks")

      for {block, direction} <- [{first, "up"}, {last, "down"}] do
        moved =
          conn
          |> tool_call(bearer, "move_article_block", %{
            "block_id" => block["id"],
            "direction" => direction
          })
          |> tool_data()

        assert Enum.map(moved["blocks"], & &1["id"]) == [first["id"], last["id"]]
      end
    end

    test "rejects a direction it does not understand", %{conn: conn, bearer: bearer} do
      article = conn |> tool_call(bearer, "create_article", %{"title" => "X"}) |> tool_data()

      block =
        conn
        |> tool_call(bearer, "add_article_block", %{
          "article_id" => article["id"],
          "type" => "richtext",
          "body" => "x"
        })
        |> tool_data()

      assert conn
             |> tool_call(bearer, "move_article_block", %{
               "block_id" => block["id"],
               "direction" => "sideways"
             })
             |> tool_error() =~ ~s("up" or "down")
    end

    test "creates and updates every block type", %{conn: conn, bearer: bearer} do
      article = conn |> tool_call(bearer, "create_article", %{"title" => "X"}) |> tool_data()

      add = fn type, args ->
        conn
        |> tool_call(
          bearer,
          "add_article_block",
          Map.merge(%{"article_id" => article["id"], "type" => type}, args)
        )
        |> tool_data()
      end

      update = fn id, args ->
        conn
        |> tool_call(bearer, "update_article_block", Map.merge(%{"block_id" => id}, args))
        |> tool_data()
      end

      alert = add.("alert", %{"icon" => "info", "body" => "Achtung"})
      assert alert["icon"] == "info"
      assert update.(alert["id"], %{"icon" => "warning"})["icon"] == "warning"

      upload = upload_fixture()

      card =
        add.("media_card", %{
          "title" => "Karte",
          "body" => "Text",
          "image_media_id" => upload.id,
          "image_position" => "left"
        })

      assert card["image"]["id"] == upload.id
      assert card["image_position"] == "left"

      updated_card = update.(card["id"], %{"image_position" => "right", "shadow" => true})
      assert updated_card["image_position"] == "right"
      assert updated_card["shadow"]

      gallery = add.("image_gallery", %{"title" => "Bilder", "layout" => "grid"})
      assert gallery["layout"] == "grid"

      updated_gallery =
        update.(gallery["id"], %{"layout" => "slideshow", "aspect_ratio" => "4:3"})

      assert updated_gallery["layout"] == "slideshow"
      assert updated_gallery["aspect_ratio"] == "4:3"

      people = add.("person_list", %{"title" => "Vorstand", "display_style" => "table"})
      assert people["display_style"] == "table"

      updated_people =
        update.(people["id"], %{"display_style" => "cards", "filter_roles" => ["vorsitzender"]})

      assert updated_people["display_style"] == "cards"
      assert updated_people["filter_roles"] == ["vorsitzender"]

      separator = add.("separator", %{})
      assert separator["type"] == "separator"
    end

    test "rejects an invalid value for a block field", %{conn: conn, bearer: bearer} do
      article = conn |> tool_call(bearer, "create_article", %{"title" => "X"}) |> tool_data()

      block =
        conn
        |> tool_call(bearer, "add_article_block", %{
          "article_id" => article["id"],
          "type" => "image_gallery"
        })
        |> tool_data()

      assert conn
             |> tool_call(bearer, "update_article_block", %{
               "block_id" => block["id"],
               "aspect_ratio" => "21:9"
             })
             |> tool_error() =~ "aspect_ratio"
    end

    test "rejects an unknown block type with the valid ones named", %{conn: conn, bearer: bearer} do
      article = conn |> tool_call(bearer, "create_article", %{"title" => "X"}) |> tool_data()

      error =
        conn
        |> tool_call(bearer, "add_article_block", %{
          "article_id" => article["id"],
          "type" => "video"
        })
        |> tool_error()

      assert error =~ "richtext"
      assert error =~ ~s(Unknown block type "video")
    end

    test "finds articles by title, including drafts", %{conn: conn, bearer: bearer} do
      article_fixture(%{title: "Königsball", status: "draft"})
      article_fixture(%{title: "Etwas anderes"})

      result = conn |> tool_call(bearer, "search_articles", %{"query" => "königs"}) |> tool_data()

      assert result["total"] == 1
      assert [%{"title" => "Königsball"}] = result["articles"]
    end

    test "reports a changeset failure as a readable result, not a protocol error", %{
      conn: conn,
      bearer: bearer
    } do
      article = conn |> tool_call(bearer, "create_article", %{"title" => "X"}) |> tool_data()

      conn
      |> tool_call(bearer, "update_article", %{
        "article_id" => article["id"],
        "status" => "bogus"
      })
      |> tool_error()
      |> then(&assert(&1 =~ "status"))
    end

    test "reports a missing required argument", %{conn: conn, bearer: bearer} do
      assert conn |> tool_call(bearer, "create_article", %{}) |> tool_error() =~ ~s("title")
    end

    test "reports an unknown article id without raising", %{conn: conn, bearer: bearer} do
      assert conn
             |> tool_call(bearer, "get_article", %{"article_id" => "not-a-uuid"})
             |> tool_error() =~ "No article"
    end

    test "will not resolve a page block through the article tools", %{conn: conn, bearer: bearer} do
      page = page_fixture()
      richtext_block_fixture(page)
      [{page_block, _}] = Content.load_blocks(page)

      assert conn
             |> tool_call(bearer, "update_article_block", %{
               "block_id" => page_block.id,
               "body" => "übernommen"
             })
             |> tool_error() =~ "No article block"
    end
  end

  describe "media tools" do
    test "searches the library and returns usable ids and urls", %{conn: conn, bearer: bearer} do
      upload = upload_fixture(%{filename: "koenigsball.webp", title: "Königsball"})

      result =
        conn |> tool_call(bearer, "search_media", %{"query" => "koenigsball"}) |> tool_data()

      assert [found] = result["media"]
      assert found["id"] == upload.id
      assert found["url"] =~ "/media/"
    end

    test "attaches an existing media item to a gallery block", %{conn: conn, bearer: bearer} do
      article = conn |> tool_call(bearer, "create_article", %{"title" => "X"}) |> tool_data()
      upload = upload_fixture()

      gallery =
        conn
        |> tool_call(bearer, "add_article_block", %{
          "article_id" => article["id"],
          "type" => "image_gallery",
          "title" => "Impressionen"
        })
        |> tool_data()

      filled =
        conn
        |> tool_call(bearer, "add_gallery_image", %{
          "block_id" => gallery["id"],
          "media_id" => upload.id
        })
        |> tool_data()

      assert [%{"media" => %{"id" => media_id}}] = filled["images"]
      assert media_id == upload.id
    end

    test "refuses to fill a block that is not a gallery", %{conn: conn, bearer: bearer} do
      article = conn |> tool_call(bearer, "create_article", %{"title" => "X"}) |> tool_data()

      block =
        conn
        |> tool_call(bearer, "add_article_block", %{
          "article_id" => article["id"],
          "type" => "richtext",
          "body" => "text"
        })
        |> tool_data()

      assert conn
             |> tool_call(bearer, "add_gallery_image", %{
               "block_id" => block["id"],
               "media_id" => upload_fixture().id
             })
             |> tool_error() =~ "not image_gallery"
    end
  end

  describe "authorization follows the user, not the token" do
    test "a calendar editor can call nothing here", %{conn: conn} do
      user = user_fixture()
      {:ok, user} = Bbh.Accounts.update_user_role(user, "calendar_editor")
      {:ok, bearer, _} = ApiTokens.create_pat(user, "test", ["mcp:read", "mcp:write"])

      # Deliberately generic: the message must not name the internal section an
      # unauthorized caller was refused.
      error = conn |> tool_call(bearer, "search_articles", %{}) |> tool_error()
      assert error =~ "not permitted"
      refute error =~ "articles"

      tools =
        conn
        |> rpc(bearer, %{jsonrpc: "2.0", id: 1, method: "tools/list"})
        |> json_response(200)
        |> get_in(["result", "tools"])

      assert tools == []
    end

    test "a read-only token cannot write", %{conn: conn, user: user} do
      {:ok, bearer, _} = ApiTokens.create_pat(user, "ro", ["mcp:read"])

      assert conn
             |> tool_call(bearer, "create_article", %{"title" => "Nope"})
             |> tool_error() =~ "mcp:write"

      assert Content.count_articles() == 0
    end
  end
end
