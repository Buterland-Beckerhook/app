defmodule BbhWeb.MCP.View do
  @moduledoc """
  Serializes contexts structs into the plain maps the MCP tools return.

  Two rules shape everything here:

    * **Ids the model can act on.** A block is identified by its `article_blocks` join id,
      because that is what `Bbh.Content.update_block/2` and `move_block/2` take. Handing
      back the concrete block's own id would look equally plausible and fail on use.
    * **Absolute URLs.** The caller is an assistant on a phone, not a browser on the site,
      so a bare `/media/...` path is not something it can open or show anyone.

  Image metadata is read off the media item (`title`, `caption`, `copyright`), never off
  the embedding — the same rule the templates follow, see
  `docs/adr/0004-media-library-owns-image-metadata.md`.

  One deliberate difference from a rendered page: block bodies come back as the raw stored
  HTML, so any `mailto:` or plain-text address in them is **not** obfuscated.
  `BbhWeb.EmailObfuscation.rewrite/1` runs inside `BbhWeb.Format.render_richtext/1`, i.e.
  at template render, and this is not one. That is correct here — the caller is the
  authenticated owner of the content reading their own draft, not a public page — but it is
  the kind of thing that reads like an oversight later, so: it is not one. See
  `docs/adr/0005-email-obfuscation.md`.
  """
  use BbhWeb, :verified_routes

  alias Bbh.Content.Article
  alias Bbh.Media.Upload
  alias BbhWeb.Format

  @doc "Compact article shape for list results."
  def article_summary(%Article{} = a) do
    %{
      id: a.id,
      title: a.title,
      subtitle: a.subtitle,
      slug: a.slug,
      year: a.year,
      status: a.status,
      date_published: a.date_published,
      url: article_url(a)
    }
  end

  @doc "Full article shape, including its ordered content blocks."
  def article(%Article{} = a, blocks) do
    a
    |> article_summary()
    |> Map.merge(%{
      author: a.author,
      tags: a.tags,
      date_modified: a.date_modified,
      no_article: a.no_article,
      image: media(a.image),
      blocks: Enum.map(blocks, fn {join, block} -> block(join, block) end)
    })
  end

  @doc """
  A public article URL, or `nil` while the article has no publish date yet.

  A draft still gets a URL: an editor is allowed to preview it, and it is what the
  assistant should hand the user to check its work.
  """
  def article_url(%Article{year: year, slug: slug}) when is_integer(year) and is_binary(slug),
    do: url(~p"/aktuell/#{year}/#{slug}")

  def article_url(_), do: nil

  @doc "Media item shape. `nil` in, `nil` out, so callers need no guard for an unset image."
  def media(nil), do: nil
  def media(%Ecto.Association.NotLoaded{}), do: nil

  def media(%Upload{} = u) do
    %{
      id: u.id,
      filename: u.filename,
      title: u.title,
      # Named "alt_text" rather than "description" so a model reaching for the accessible
      # text finds it; `description` is what the column is called, and it reads as prose.
      alt_text: u.description,
      caption: u.caption,
      copyright: u.copyright,
      content_type: u.content_type,
      width: u.width,
      height: u.height,
      url: absolute(Format.media_url(u))
    }
  end

  @doc "A block-join row plus its concrete block, flattened into one map."
  def block(join, block) do
    %{
      id: join.id,
      position: join.position,
      type: join.block_type
    }
    |> Map.merge(block_fields(join.block_type, block))
  end

  defp block_fields("richtext", b), do: %{body: b.body}
  defp block_fields("alert", b), do: %{icon: b.icon, body: b.body}
  defp block_fields("separator", _b), do: %{}

  defp block_fields("media_card", b) do
    %{
      title: b.title,
      subtitle: b.subtitle,
      body: b.body,
      image_position: b.image_position,
      shadow: b.shadow,
      title_above: b.title_above,
      show_credit: b.show_credit,
      image: media(b.image)
    }
  end

  defp block_fields("image_gallery", b) do
    %{
      title: b.title,
      layout: b.layout,
      lightbox: b.lightbox,
      aspect_ratio: b.aspect_ratio,
      autoplay: b.autoplay,
      images: gallery_files(b.files)
    }
  end

  defp block_fields("person_list", b) do
    %{
      title: b.title,
      filter_roles: b.filter_roles,
      filter_honorary: b.filter_honorary,
      display_style: b.display_style,
      show_address: b.show_address,
      only_active: b.only_active,
      sort_by: b.sort_by
    }
  end

  defp gallery_files(%Ecto.Association.NotLoaded{}), do: []

  defp gallery_files(files) when is_list(files),
    do: Enum.map(files, &%{id: &1.id, sort: &1.sort, media: media(&1.media)})

  defp gallery_files(_), do: []

  # `media_url/2` always yields a path for a loaded upload, which is the only thing that
  # reaches here.
  defp absolute(path) when is_binary(path), do: BbhWeb.Endpoint.url() <> path
end
