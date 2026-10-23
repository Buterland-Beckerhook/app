defmodule Bbh.Redirects.NotFoundPath do
  @moduledoc """
  A path that ended in a 404, aggregated per normalized path. Feeds the „Nicht
  gefunden“ list in `/admin/weiterleitungen`, where a missing redirect can be created
  with one click. Written by `Bbh.Redirects.record_not_found/2`, swept by
  `Bbh.Workers.NotFoundPruner`.
  """
  use Bbh.Schema

  schema "not_found_paths" do
    field :path, :string
    field :hits, :integer, default: 1
    field :referrer, :string
    field :first_seen_at, :utc_datetime
    field :last_seen_at, :utc_datetime
  end
end
