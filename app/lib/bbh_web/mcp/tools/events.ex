defmodule BbhWeb.MCP.Tools.Events do
  @moduledoc """
  Read-only event lookup, so an article's "event" block can name its event.

  Events are managed in `/admin/termine`; nothing here writes one. The list is the same
  the block editor offers (`Bbh.Calendar.block_event_options/2`).
  """
  alias BbhWeb.MCP.Args
  alias BbhWeb.MCP.View

  @max_limit 100

  def search_events(args, _scope) do
    limit = args |> Args.integer("limit", 20) |> max(1) |> min(@max_limit)

    events =
      Bbh.Calendar.block_event_options(Bbh.Time.now(),
        query: Args.string(args, "query"),
        limit: limit
      )

    {:ok, %{events: Enum.map(events, &View.event_option/1)}}
  end
end
