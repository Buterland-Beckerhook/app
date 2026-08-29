defmodule BbhWeb.MCP.ServerTest do
  use Bbh.DataCase, async: true

  import Bbh.AccountsFixtures

  alias Bbh.Accounts
  alias Bbh.Accounts.Scope
  alias Bbh.ApiTokens.ApiToken
  alias BbhWeb.MCP
  alias BbhWeb.MCP.Server

  # The token only has to carry scopes here; nothing in the protocol layer reads the rest.
  defp token(scopes), do: %ApiToken{scopes: scopes}

  defp admin_scope, do: Scope.for_user(admin_user_fixture())

  defp request(method, params \\ %{}, id \\ 1) do
    %{"jsonrpc" => "2.0", "id" => id, "method" => method, "params" => params}
  end

  defp call(method, params, scope, scopes \\ ["mcp:read", "mcp:write"]) do
    {:reply, response} = Server.handle(request(method, params), scope, token(scopes))
    response
  end

  describe "initialize" do
    test "echoes a protocol revision it supports" do
      for version <- MCP.supported_versions() do
        response =
          call("initialize", %{"protocolVersion" => version}, admin_scope())

        assert response.result.protocolVersion == version
      end
    end

    test "answers with its own revision when the client asks for one it does not speak" do
      response = call("initialize", %{"protocolVersion" => "2024-11-05"}, admin_scope())

      assert response.result.protocolVersion == MCP.preferred_version()
    end

    test "advertises tools and warns the model off publishing" do
      response = call("initialize", %{}, admin_scope())

      assert response.result.capabilities.tools
      assert response.result.serverInfo.name == "buterland-beckerhook"
      assert response.result.instructions =~ "drafts"
      assert response.result.instructions =~ "push notification"
    end
  end

  describe "protocol basics" do
    test "ping answers empty" do
      assert call("ping", %{}, admin_scope()).result == %{}
    end

    test "an unknown method is a method-not-found error" do
      response = call("nonsense/method", %{}, admin_scope())

      assert response.error.code == -32601
      assert response.error.message =~ "nonsense/method"
    end

    test "a notification is acknowledged without a response" do
      message = %{"jsonrpc" => "2.0", "method" => "notifications/initialized"}

      assert Server.handle(message, admin_scope(), token([])) == :accepted
    end

    test "a batch is rejected — the protocol removed them" do
      assert {:error, response} = Server.handle([request("ping")], admin_scope(), token([]))
      assert response.error.code == -32600
      assert response.error.message =~ "Batch"
    end

    test "a message that is not JSON-RPC at all is rejected" do
      assert {:error, response} = Server.handle(%{"hello" => "world"}, admin_scope(), token([]))
      assert response.error.code == -32600
    end

    test "the response carries the request id back" do
      {:reply, response} = Server.handle(request("ping", %{}, 42), admin_scope(), token([]))
      assert response.id == 42
    end
  end

  describe "tools/list is filtered by role and scope" do
    defp tool_names(scope, scopes) do
      call("tools/list", %{}, scope, scopes).result.tools |> Enum.map(& &1.name)
    end

    test "an admin with a full token sees every tool" do
      names = tool_names(admin_scope(), ["mcp:read", "mcp:write"])

      assert "create_article" in names
      assert "search_media" in names
    end

    test "an editor sees the content tools" do
      # "editor" is the default role for a new user.
      names = tool_names(Scope.for_user(user_fixture()), ["mcp:read", "mcp:write"])

      assert "create_article" in names
      assert "search_media" in names
    end

    test "a calendar editor sees nothing — the MCP server covers no calendar tools" do
      user = user_fixture()
      {:ok, user} = Accounts.update_user_role(user, "calendar_editor")

      assert tool_names(Scope.for_user(user), ["mcp:read", "mcp:write"]) == []
    end

    test "a read-only token hides every write tool" do
      names = tool_names(admin_scope(), ["mcp:read"])

      assert "search_articles" in names
      assert "get_article" in names
      assert "search_media" in names
      refute "create_article" in names
      refute "update_article" in names
      refute "add_article_block" in names
    end

    test "mcp:write implies mcp:read, so a write token can still look ids up" do
      names = tool_names(admin_scope(), ["mcp:write"])

      assert "search_articles" in names
      assert "create_article" in names
    end

    test "an anonymous scope sees nothing and does not raise" do
      assert tool_names(nil, ["mcp:read", "mcp:write"]) == []
    end

    test "no tool deletes anything" do
      names = tool_names(admin_scope(), ["mcp:read", "mcp:write"])

      refute Enum.any?(names, &String.contains?(&1, "delete"))
      refute Enum.any?(names, &String.contains?(&1, "remove"))
      refute Enum.any?(names, &String.contains?(&1, "destroy"))
    end

    test "every advertised tool declares an object input schema" do
      for tool <- call("tools/list", %{}, admin_scope()).result.tools do
        assert tool.inputSchema.type == "object"
        assert is_map(tool.inputSchema.properties)
        assert is_list(tool.inputSchema.required)
      end
    end
  end

  describe "tools/call" do
    test "an unknown tool name is an invalid-params error, not a failed result" do
      response =
        call("tools/call", %{"name" => "delete_everything", "arguments" => %{}}, admin_scope())

      assert response.error.code == -32602
    end

    test "a missing name is an invalid-params error" do
      assert call("tools/call", %{}, admin_scope()).error.code == -32602
    end

    test "a tool the caller may not use fails as a result, so the model can read why" do
      response =
        call(
          "tools/call",
          %{"name" => "create_article", "arguments" => %{"title" => "x"}},
          admin_scope(),
          ["mcp:read"]
        )

      assert response.result.isError
      assert hd(response.result.content).text =~ "mcp:write"
    end
  end
end
