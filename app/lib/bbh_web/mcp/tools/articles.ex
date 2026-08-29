defmodule BbhWeb.MCP.Tools.Articles do
  @moduledoc """
  Article and content-block tools. Every function delegates to `Bbh.Content`, so an MCP
  write goes through the same changesets, sanitization and search reindexing as the admin
  form — there is no second write path to keep in sync.

  Nothing here deletes. Removing an article, a block or a gallery image stays a deliberate
  act in `/admin`; see `docs/adr/0009-mcp-server.md`.
  """
  alias Bbh.Content
  alias BbhWeb.MCP.Args
  alias BbhWeb.MCP.View

  @max_limit 100

  ## Reads

  def search_articles(args, _scope) do
    query = Args.string(args, "query")
    status = Args.string(args, "status")
    limit = args |> Args.integer("limit", 20) |> clamp(1, @max_limit)
    offset = args |> Args.integer("offset", 0) |> max(0)

    # Filtered in memory over the full list, exactly like the admin index does via
    # `BbhWeb.AdminList.process/3` — the club has hundreds of articles, not millions.
    matches =
      Content.list_articles()
      |> Enum.filter(&matches?(&1, query, status))

    {:ok,
     %{
       total: length(matches),
       limit: limit,
       offset: offset,
       articles: matches |> Enum.slice(offset, limit) |> Enum.map(&View.article_summary/1)
     }}
  end

  defp matches?(article, query, status) do
    matches_query?(article, query) and (is_nil(status) or article.status == status)
  end

  defp matches_query?(_article, nil), do: true

  defp matches_query?(article, query) do
    needle = String.downcase(query)

    [article.title, article.subtitle, article.slug]
    |> Enum.any?(&(is_binary(&1) and String.contains?(String.downcase(&1), needle)))
  end

  def get_article(args, _scope) do
    with {:ok, article} <- lookup_article(args) do
      {:ok, View.article(article, Content.load_blocks(article))}
    end
  end

  ## Writes — article

  def create_article(args, _scope) do
    with {:ok, title} <- Args.require_string(args, "title") do
      attrs =
        args
        |> Args.take(%{
          "subtitle" => :subtitle,
          "author" => :author,
          "date_published" => :date_published,
          "no_article" => :no_article
        })
        |> Map.merge(%{
          title: title,
          slug: Args.string(args, "slug") || Bbh.Slug.slugify(title),
          # Draft unless the caller says otherwise: publishing puts the article on the
          # front page and fires a web push to every subscriber within five minutes
          # (Bbh.Workers.ArticlePublishNotifier). That must be an explicit act.
          status: Args.string(args, "status", "draft"),
          tags: Args.string_list(args, "tags", [])
        })
        |> Map.put_new(:date_published, Bbh.Time.now())
        |> put_image(args)

      attrs
      |> Content.create_article()
      |> reply_article()
    end
  end

  def update_article(args, _scope) do
    with {:ok, article} <- fetch_article(args) do
      attrs =
        args
        |> Args.take(%{
          "title" => :title,
          "subtitle" => :subtitle,
          "slug" => :slug,
          "status" => :status,
          "author" => :author,
          "date_published" => :date_published,
          "no_article" => :no_article
        })
        |> maybe_put_tags(args)
        |> put_image(args)

      article
      |> Content.update_article(attrs)
      |> reply_article()
    end
  end

  def set_article_image(args, _scope) do
    with {:ok, article} <- fetch_article(args),
         {:ok, media_id} <- optional_media_id(args) do
      article
      |> Content.set_article_image(media_id)
      |> reply_article()
    end
  end

  ## Writes — blocks

  def add_article_block(args, _scope) do
    with {:ok, article} <- fetch_article(args),
         {:ok, type} <- fetch_block_type(args),
         {:ok, attrs} <- block_attrs(type, args),
         # `add_block/2` inserts with `Repo.insert!`, so today it either returns `{:ok, _}`
         # or raises. Matching it explicitly keeps that an assertion rather than a silent
         # assumption: were it ever to return an error tuple, this would fail loudly here
         # instead of returning an unmatched value to `Tools.result/1`.
         {:ok, join} <- Content.add_block(article, type) do
      # `add_block/2` only appends an empty block of the type; the caller's fields are a
      # second step, the same two steps the editor takes when you add a block and save it.
      case Content.update_block(join, attrs) do
        {:ok, _block} -> reply_block(join)
        {:error, changeset} -> {:error, Args.errors(changeset)}
      end
    end
  end

  def update_article_block(args, _scope) do
    with {:ok, join} <- fetch_block(args),
         {:ok, attrs} <- block_attrs(join.block_type, args) do
      case Content.update_block(join, attrs) do
        {:ok, _block} -> reply_block(join)
        {:error, changeset} -> {:error, Args.errors(changeset)}
      end
    end
  end

  def move_article_block(args, _scope) do
    with {:ok, join} <- fetch_block(args),
         {:ok, direction} <- fetch_direction(args) do
      # `move_block/2` answers `{:ok, _}` for a real move, `{:ok, :noop}` at a list edge,
      # and `{:error, :not_found}` for a row that is not in its owner's list. Matched
      # exhaustively so a new return value cannot slip through as a success.
      case Content.move_block(join, direction) do
        {:ok, _moved} ->
          article = Content.get_article!(join.article_id)
          {:ok, View.article(article, Content.load_blocks(article))}

        {:error, :not_found} ->
          {:error, "Block #{join.id} is not part of its article's block list."}
      end
    end
  end

  def add_gallery_image(args, _scope) do
    with {:ok, join} <- fetch_block(args),
         :ok <- require_type(join, "image_gallery"),
         {:ok, media_id} <- required_media_id(args) do
      case Content.add_gallery_file(Content.get_block(join), media_id) do
        {:ok, _file} -> reply_block(join)
        {:error, changeset} -> {:error, Args.errors(changeset)}
      end
    end
  end

  ## Argument plumbing

  # Writes address an article by id only. `slug` is an editable *field* on the write
  # tools, so accepting it as a lookup key too would make "rename this article" ambiguous
  # with "find the article now called this".
  defp fetch_article(args) do
    with {:ok, id} <- Args.require_string(args, "article_id") do
      case Content.get_article(id) do
        nil -> {:error, "No article with id #{id}."}
        article -> {:ok, article}
      end
    end
  end

  # Reads may address an article either way, since `get_article` changes nothing.
  defp lookup_article(args) do
    cond do
      id = Args.string(args, "article_id") || Args.string(args, "id") ->
        case Content.get_article(id) do
          nil -> {:error, "No article with id #{id}."}
          article -> {:ok, article}
        end

      slug = Args.string(args, "slug") ->
        case Args.integer(args, "year", nil) do
          nil ->
            {:error, ~s(Looking up by "slug" also needs "year".)}

          year ->
            case Content.get_article_by_slug_year(slug, year) do
              nil -> {:error, ~s(No article with slug "#{slug}" in year #{year}.)}
              article -> {:ok, article}
            end
        end

      true ->
        {:error, ~s(Provide "article_id", or "slug" together with "year".)}
    end
  end

  defp fetch_block(args) do
    with {:ok, id} <- Args.require_string(args, "block_id") do
      case Content.get_article_block(id) do
        nil -> {:error, "No article block with id #{id}."}
        join -> {:ok, join}
      end
    end
  end

  defp fetch_block_type(args) do
    types = Map.keys(Bbh.Content.Blocks.types())

    with {:ok, type} <- Args.require_string(args, "type") do
      if type in types,
        do: {:ok, type},
        else: {:error, ~s(Unknown block type "#{type}". Valid: #{Enum.join(types, ", ")}.)}
    end
  end

  defp fetch_direction(args) do
    case Args.string(args, "direction") do
      "up" -> {:ok, :up}
      "down" -> {:ok, :down}
      _ -> {:error, ~s(Argument "direction" must be "up" or "down".)}
    end
  end

  defp require_type(join, expected) do
    if join.block_type == expected,
      do: :ok,
      else: {:error, "Block #{join.id} is a #{join.block_type} block, not #{expected}."}
  end

  defp required_media_id(args) do
    with {:ok, id} <- Args.require_string(args, "media_id") do
      if Bbh.Media.get_upload(id),
        do: {:ok, id},
        else: {:error, "No media item with id #{id}. Use search_media to find one."}
    end
  end

  # `media_id: null` is meaningful here — it clears the article image — so an explicit
  # null must be told apart from the argument being absent.
  defp optional_media_id(args) do
    case Map.get(args, "media_id") do
      nil -> {:ok, nil}
      _ -> required_media_id(args)
    end
  end

  defp put_image(attrs, args) do
    case Args.string(args, "image_media_id") do
      nil -> attrs
      id -> Map.put(attrs, :image_id, id)
    end
  end

  defp maybe_put_tags(attrs, args) do
    case Args.string_list(args, "tags") do
      nil -> attrs
      tags -> Map.put(attrs, :tags, tags)
    end
  end

  ## Block attributes

  defp block_attrs("richtext", args), do: with_body(%{}, args)
  defp block_attrs("separator", _args), do: {:ok, %{}}

  defp block_attrs("alert", args) do
    %{} |> merge_take(args, %{"icon" => :icon}) |> with_body(args)
  end

  defp block_attrs("media_card", args) do
    %{}
    |> merge_take(args, %{
      "title" => :title,
      "subtitle" => :subtitle,
      "image_position" => :image_position,
      "shadow" => :shadow,
      "title_above" => :title_above,
      "show_credit" => :show_credit
    })
    |> put_image_as(args, "image_media_id", :image_id)
    |> with_body(args)
  end

  defp block_attrs("image_gallery", args) do
    {:ok,
     merge_take(%{}, args, %{
       "title" => :title,
       "layout" => :layout,
       "lightbox" => :lightbox,
       "aspect_ratio" => :aspect_ratio,
       "autoplay" => :autoplay
     })}
  end

  defp block_attrs("person_list", args) do
    attrs =
      merge_take(%{}, args, %{
        "title" => :title,
        "filter_honorary" => :filter_honorary,
        "display_style" => :display_style,
        "show_address" => :show_address,
        "only_active" => :only_active,
        "sort_by" => :sort_by
      })

    {:ok,
     case Args.string_list(args, "filter_roles") do
       nil -> attrs
       roles -> Map.put(attrs, :filter_roles, roles)
     end}
  end

  defp merge_take(attrs, args, fields), do: Map.merge(attrs, Args.take(args, fields))

  defp put_image_as(attrs, args, arg, key) do
    case Args.string(args, arg) do
      nil -> attrs
      id -> Map.put(attrs, key, id)
    end
  end

  # Renders the caller's `body` into the stored HTML shape.
  #
  # Markdown is the default because that is what a model writes unprompted. It is rendered
  # with raw-HTML passthrough on purpose: `Bbh.Html.sanitize/1` runs inside the changeset
  # a moment later and is the actual security boundary — the very same one every Quill
  # edit crosses — so escaping here would only mangle legitimate markup.
  #
  # `to_editor/1` then inserts the blank paragraph that `sanitize/1` reads as a hard
  # paragraph break. Without it the sanitizer's paragraph merge would collapse the whole
  # text into a single `<p>` joined by `<br />`; see `Bbh.Html`.
  defp with_body(attrs, args) do
    case Map.get(args, "body") do
      nil ->
        {:ok, attrs}

      body when is_binary(body) ->
        case Args.string(args, "format", "markdown") do
          "markdown" -> {:ok, Map.put(attrs, :body, body |> markdown_to_html() |> to_editor())}
          "html" -> {:ok, Map.put(attrs, :body, to_editor(body))}
          other -> {:error, ~s(Argument "format" must be "markdown" or "html", got "#{other}".)}
        end

      _ ->
        {:error, ~s(Argument "body" must be a string.)}
    end
  end

  defp markdown_to_html(body) do
    MDEx.to_html!(body,
      extension: [table: true, strikethrough: true, autolink: true, tasklist: true],
      render: [unsafe: true]
    )
  end

  defp to_editor(html), do: Bbh.Html.to_editor(html)

  ## Replies

  defp reply_article({:ok, article}) do
    article = Content.get_article!(article.id)
    {:ok, View.article(article, Content.load_blocks(article))}
  end

  defp reply_article({:error, %Ecto.Changeset{} = changeset}),
    do: {:error, Args.errors(changeset)}

  # Re-read the join so `position` reflects any renumbering, and the block so the reply
  # shows what was actually stored after sanitization rather than what was sent.
  defp reply_block(join) do
    join = Content.get_article_block(join.id)
    {:ok, View.block(join, Content.get_block(join))}
  end

  defp clamp(value, min, max), do: value |> max(min) |> min(max)
end
