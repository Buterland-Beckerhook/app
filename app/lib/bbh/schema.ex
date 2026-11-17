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

  @doc """
  An id from outside (a URL, a form, an MCP argument) as a UUID: `{:ok, uuid}`, or
  `:error` for anything that is not one — `nil` and non-strings included — so a lookup
  can treat a malformed id as a miss instead of raising in the query.
  """
  def cast_id(id) when is_binary(id), do: Ecto.UUID.cast(id)
  def cast_id(_id), do: :error
end
