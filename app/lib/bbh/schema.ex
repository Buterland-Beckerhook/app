defmodule Bbh.Schema do
  @moduledoc """
  Shared schema setup: UUID primary keys, UUID foreign keys, and UTC timestamps.
  `use Bbh.Schema` in place of `use Ecto.Schema`.
  """
  defmacro __using__(_opts) do
    quote do
      use Ecto.Schema
      import Ecto.Changeset

      @primary_key {:id, :binary_id, autogenerate: true}
      @foreign_key_type :binary_id
      @timestamps_opts [type: :utc_datetime]
    end
  end
end
