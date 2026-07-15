defmodule Bbh.Accounts.CoseKey do
  @moduledoc """
  Ecto type that stores a WebAuthn COSE public key.

  Wax hands back the credential public key as an Erlang map with integer keys
  (the COSE label/value pairs), which is not JSON-safe. We persist it as an
  opaque binary via the term encoding and load it back with the `:safe` option
  — the data only ever originates from our own `Wax.register/3` result, never
  from user input.
  """
  use Ecto.Type

  @impl true
  def type, do: :binary

  @impl true
  def cast(%{} = key), do: {:ok, key}
  def cast(_), do: :error

  @impl true
  def dump(%{} = key), do: {:ok, :erlang.term_to_binary(key)}
  def dump(_), do: :error

  @impl true
  def load(bin) when is_binary(bin) do
    {:ok, :erlang.binary_to_term(bin, [:safe])}
  rescue
    ArgumentError -> :error
  end

  def load(_), do: :error
end
