defmodule BbhWeb.MCP.Tools.Media do
  @moduledoc """
  Read-only access to the media library.

  There is no upload tool. Photos reach the library through `/admin/medien`, which
  sniffs the real file type, enforces the megapixel budget and pre-warms the responsive
  variants; MCP only finds what is already there and hands the id to the article tools.
  """
  alias Bbh.Media
  alias BbhWeb.MCP.Args
  alias BbhWeb.MCP.View

  @max_limit 100

  def search_media(args, _scope) do
    limit = args |> Args.integer("limit", 20) |> clamp(1, @max_limit)
    offset = args |> Args.integer("offset", 0) |> max(0)

    # `list_uploads/1` has no limit of its own; the library is a few thousand rows, and
    # slicing here keeps the tool result small enough to be worth reading.
    uploads =
      Media.list_uploads(
        search: Args.string(args, "query"),
        images_only: Args.boolean(args, "images_only", true),
        sort: Args.string(args, "sort", "newest")
      )

    {:ok,
     %{
       total: length(uploads),
       limit: limit,
       offset: offset,
       media: uploads |> Enum.slice(offset, limit) |> Enum.map(&View.media/1)
     }}
  end

  defp clamp(value, min, max), do: value |> max(min) |> min(max)
end
