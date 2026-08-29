defmodule BbhWeb.MCP.Tools do
  @moduledoc """
  The tool registry: what `tools/list` advertises and what `tools/call` dispatches to.

  Two things are load-bearing here.

  **`tools/list` is filtered, not just `tools/call` guarded.** A caller is shown only the
  tools their role and token scopes actually permit, so a `calendar_editor` sees an empty
  list rather than a menu of tools that all fail. `call/4` re-checks anyway — a client may
  call a name it was never offered.

  **Domain failures are results, not protocol errors.** A rejected changeset comes back as
  `isError: true` with the field errors as text, which the model can read and correct.
  JSON-RPC error codes stay reserved for protocol and auth problems, so "fix your input"
  never looks like "the server is broken".
  """
  alias Bbh.Accounts.User
  alias BbhWeb.Authz
  alias BbhWeb.MCP.Tools.Articles
  alias BbhWeb.MCP.Tools.Media

  require Logger

  @statuses ~w(draft published archived)
  @block_types ~w(richtext alert media_card image_gallery person_list separator)

  @doc "Every tool this server knows, regardless of who is asking."
  def all, do: articles_tools() ++ media_tools()

  @doc """
  The tools `scope`'s user may call with `api_token`, in `tools/list` wire shape.

  An anonymous scope yields an empty list rather than raising — `Scope.for_user(nil)` is
  `nil`, and this is reachable from the plug's assigns.
  """
  def list_for(scope, api_token) do
    all()
    |> Enum.filter(&allowed?(&1, user(scope), scopes(api_token)))
    |> Enum.map(&%{name: &1.name, description: &1.description, inputSchema: &1.input_schema})
  end

  @doc """
  Runs the named tool.

  Returns the `tools/call` result map. `{:error, :unknown_tool}` is the one case that is
  not a result: an unknown name is a protocol-level mistake, not a failed operation.
  """
  def call(name, args, scope, api_token) when is_map(args) do
    user = user(scope)

    case Enum.find(all(), &(&1.name == name)) do
      nil ->
        {:error, :unknown_tool}

      tool ->
        if allowed?(tool, user, scopes(api_token)) do
          if tool.write?, do: Logger.info("MCP #{name} by #{user.email}")
          {module, function} = tool.handler
          {:ok, result(apply(module, function, [args, scope]))}
        else
          {:ok, error_result(denial(tool, user))}
        end
    end
  end

  def call(_name, _args, _scope, _api_token),
    do: {:ok, error_result(~s(The "arguments" field must be an object.))}

  ## Authorization

  defp allowed?(tool, %User{} = user, scopes) do
    Authz.can_access_section?(user, tool.section) and required_scope(tool) in scopes
  end

  defp allowed?(_tool, _user, _scopes), do: false

  defp required_scope(%{write?: true}), do: "mcp:write"
  defp required_scope(_tool), do: "mcp:read"

  # `mcp:write` implies `mcp:read`: a write-only token could otherwise never look up the
  # ids it needs to write to. The spec requires servers to honour such hierarchies.
  defp scopes(%{scopes: scopes}) do
    if "mcp:write" in scopes, do: ["mcp:read" | scopes], else: scopes
  end

  defp scopes(_), do: []

  defp user(%{user: %User{} = user}), do: user
  defp user(_), do: nil

  # The scope case names the missing scope, because the caller can act on that — mint a
  # token with it. The role case stays generic: naming the internal section would tell an
  # unauthorized caller how this server is carved up, and they can do nothing with it.
  defp denial(tool, user) do
    if Authz.can_access_section?(user, tool.section) do
      "This token lacks the #{required_scope(tool)} scope."
    else
      "Your account is not permitted to use this tool."
    end
  end

  ## Result envelopes

  defp result({:ok, data}) do
    %{content: [%{type: "text", text: Jason.encode!(data, pretty: true)}], isError: false}
  end

  defp result({:error, message}) when is_binary(message), do: error_result(message)

  defp error_result(message),
    do: %{content: [%{type: "text", text: message}], isError: true}

  ## Registry — articles

  defp articles_tools do
    [
      %{
        name: "search_articles",
        description: """
        Search articles (Artikel) by title, subtitle or slug, including drafts and
        archived ones. Returns summaries; use get_article for the full text and blocks.
        """,
        section: :articles,
        write?: false,
        handler: {Articles, :search_articles},
        input_schema:
          object(%{
            "query" => %{type: "string", description: "Substring to match, case-insensitive."},
            "status" => %{type: "string", enum: @statuses},
            "limit" => %{type: "integer", description: "Default 20, max 100."},
            "offset" => %{type: "integer", description: "Default 0."}
          })
      },
      %{
        name: "get_article",
        description: """
        Fetch one article with its ordered content blocks. Address it by article_id, or by
        slug together with year. Each block's "id" is the handle for update_article_block
        and move_article_block.
        """,
        section: :articles,
        write?: false,
        handler: {Articles, :get_article},
        input_schema:
          object(%{
            "article_id" => %{type: "string"},
            "slug" => %{type: "string"},
            "year" => %{type: "integer"}
          })
      },
      %{
        name: "create_article",
        description: """
        Create an article. It is a draft unless status says otherwise — publishing puts it
        on the front page and sends a push notification to every subscriber, so only pass
        status "published" when the user explicitly asked for that.

        Creates the article shell only; add the text with add_article_block afterwards.
        """,
        section: :articles,
        write?: true,
        handler: {Articles, :create_article},
        input_schema:
          object(
            %{
              "title" => %{type: "string"},
              "subtitle" => %{type: "string"},
              "slug" => %{
                type: "string",
                description: "Derived from the title when omitted. Must be unique per year."
              },
              "status" => %{type: "string", enum: @statuses, description: ~s(Default "draft".)},
              "date_published" => %{
                type: "string",
                description: "ISO 8601, e.g. 2026-08-28T18:00:00Z. Defaults to now."
              },
              "author" => %{type: "string"},
              "tags" => %{type: "array", items: %{type: "string"}},
              "image_media_id" => %{
                type: "string",
                description: "Media id for the hero image; find one with search_media."
              }
            },
            ["title"]
          )
      },
      %{
        name: "update_article",
        description: """
        Change an article's fields. Only the arguments you pass are touched; omitted
        fields keep their current value. Publishing an existing draft sends the push
        notification, so change status only when asked.
        """,
        section: :articles,
        write?: true,
        handler: {Articles, :update_article},
        input_schema:
          object(
            %{
              "article_id" => %{type: "string"},
              "title" => %{type: "string"},
              "subtitle" => %{type: "string"},
              "slug" => %{type: "string"},
              "status" => %{type: "string", enum: @statuses},
              "date_published" => %{type: "string", description: "ISO 8601."},
              "author" => %{type: "string"},
              "tags" => %{type: "array", items: %{type: "string"}},
              "image_media_id" => %{type: "string"}
            },
            ["article_id"]
          )
      },
      %{
        name: "set_article_image",
        description: """
        Set or clear the article's hero image. Pass media_id null to clear it. Caption and
        copyright are properties of the media item itself and are not set here.
        """,
        section: :articles,
        write?: true,
        handler: {Articles, :set_article_image},
        input_schema:
          object(
            %{
              "article_id" => %{type: "string"},
              "media_id" => %{type: ["string", "null"]}
            },
            ["article_id"]
          )
      },
      %{
        name: "add_article_block",
        description: """
        Append a content block to an article. This is how article text is written: a
        "richtext" block holds the prose, "image_gallery" holds pictures (fill it with
        add_gallery_image), "separator" draws a rule.

        Block text is Markdown by default.
        """,
        section: :articles,
        write?: true,
        handler: {Articles, :add_article_block},
        input_schema:
          object(
            Map.merge(
              %{
                "article_id" => %{type: "string"},
                "type" => %{type: "string", enum: @block_types}
              },
              block_properties()
            ),
            ["article_id", "type"]
          )
      },
      %{
        name: "update_article_block",
        description: """
        Change the fields of an existing block, addressed by the "id" get_article returns
        for it. Which arguments apply depends on the block's type; the rest are ignored.
        Replacing "body" replaces the block's whole text.
        """,
        section: :articles,
        write?: true,
        handler: {Articles, :update_article_block},
        input_schema:
          object(
            Map.merge(%{"block_id" => %{type: "string"}}, block_properties()),
            ["block_id"]
          )
      },
      %{
        name: "move_article_block",
        description: "Move a block one position up or down within its article.",
        section: :articles,
        write?: true,
        handler: {Articles, :move_article_block},
        input_schema:
          object(
            %{
              "block_id" => %{type: "string"},
              "direction" => %{type: "string", enum: ["up", "down"]}
            },
            ["block_id", "direction"]
          )
      },
      %{
        name: "add_gallery_image",
        description: """
        Append an existing media item to an image_gallery block. Find the media id with
        search_media; there is no way to upload a new file through this server.
        """,
        section: :articles,
        write?: true,
        handler: {Articles, :add_gallery_image},
        input_schema:
          object(
            %{
              "block_id" => %{type: "string", description: "An image_gallery block's id."},
              "media_id" => %{type: "string"}
            },
            ["block_id", "media_id"]
          )
      }
    ]
  end

  ## Registry — media

  defp media_tools do
    [
      %{
        name: "search_media",
        description: """
        Search the media library by filename or title. Returns each item's id, its public
        URL and its metadata (alt text, caption, copyright). Use the id with
        set_article_image or add_gallery_image.

        Uploading is not possible here — new photos go through the admin area.
        """,
        section: :media,
        write?: false,
        handler: {Media, :search_media},
        input_schema:
          object(%{
            "query" => %{type: "string", description: "Substring of filename or title."},
            "images_only" => %{type: "boolean", description: "Default true."},
            "sort" => %{type: "string", enum: ["newest", "oldest", "name"]},
            "limit" => %{type: "integer", description: "Default 20, max 100."},
            "offset" => %{type: "integer", description: "Default 0."}
          })
      }
    ]
  end

  # Fields shared by the block tools. Declared once because add_article_block and
  # update_article_block accept exactly the same set — the block's own type decides which
  # of them mean anything, and the handler drops the rest.
  defp block_properties do
    %{
      "body" => %{
        type: "string",
        description: "Text for richtext, alert and media_card blocks."
      },
      "format" => %{
        type: "string",
        enum: ["markdown", "html"],
        description: ~s(How to read "body". Default "markdown".)
      },
      "icon" => %{
        type: "string",
        enum: ["info", "warning", "success", "danger"],
        description: "alert blocks."
      },
      "title" => %{type: "string", description: "media_card, image_gallery, person_list."},
      "subtitle" => %{type: "string", description: "media_card."},
      "image_media_id" => %{type: "string", description: "media_card's picture."},
      "image_position" => %{type: "string", enum: ["left", "right"], description: "media_card."},
      "shadow" => %{type: "boolean", description: "media_card."},
      "title_above" => %{type: "boolean", description: "media_card."},
      "show_credit" => %{type: "boolean", description: "media_card."},
      "layout" => %{type: "string", enum: ["slideshow", "grid"], description: "image_gallery."},
      "lightbox" => %{type: "boolean", description: "image_gallery."},
      "aspect_ratio" => %{
        type: "string",
        enum: ["16:9", "3:2", "4:3", "1:1", "3:4", "2:3", "9:16"],
        description: "image_gallery slideshows."
      },
      "autoplay" => %{type: "boolean", description: "image_gallery slideshows."},
      "filter_roles" => %{
        type: "array",
        items: %{type: "string"},
        description: "person_list."
      },
      "filter_honorary" => %{
        type: "string",
        enum: ["all", "only", "exclude"],
        description: "person_list."
      },
      "display_style" => %{type: "string", enum: ["table", "cards"], description: "person_list."},
      "show_address" => %{type: "boolean", description: "person_list."},
      "only_active" => %{type: "boolean", description: "person_list."},
      "sort_by" => %{
        type: "string",
        enum: ["sort_order", "year_start"],
        description: "person_list."
      }
    }
  end

  defp object(properties, required \\ []) do
    %{type: "object", properties: properties, required: required}
  end
end
