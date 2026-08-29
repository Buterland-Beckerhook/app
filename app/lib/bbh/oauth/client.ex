defmodule Bbh.OAuth.Client do
  @moduledoc """
  A client registered through RFC 7591 dynamic registration.

  Public clients only: registration is open and unauthenticated, so a client secret would
  be handed to anyone who asked and protect nothing. PKCE is what binds an authorization
  code to the client that requested it.

  Because registration is open, the redirect URIs are the security boundary — see
  `validate_redirect_uris/1`. Everything else on the record is descriptive.
  """
  use Bbh.Schema

  alias Bbh.ApiTokens.ApiToken

  @grant_types ~w(authorization_code refresh_token)
  def grant_types, do: @grant_types

  # Enough for a native client that opens several loopback ports, far too few to use the
  # registry as storage.
  @max_redirect_uris 5
  @max_uri_length 2000

  schema "oauth_clients" do
    field :client_id, :string
    field :client_name, :string
    field :redirect_uris, {:array, :string}, default: []
    field :grant_types, {:array, :string}, default: []
    field :scopes, {:array, :string}, default: []

    timestamps(updated_at: false)
  end

  @doc false
  def changeset(client, attrs) do
    client
    |> cast(attrs, [:client_id, :client_name, :redirect_uris, :grant_types, :scopes])
    |> validate_required([:client_id])
    |> validate_length(:client_name, max: 200)
    |> validate_redirect_uris()
    |> validate_subset(:grant_types, @grant_types)
    |> validate_subset(:scopes, ApiToken.scopes())
    |> unique_constraint(:client_id)
  end

  @doc """
  Whether `uri` is one this client registered.

  Exact string comparison, deliberately: no prefix or wildcard matching, no normalization.
  A redirect URI is where an authorization code gets delivered, so "close enough" is the
  bug that turns an open registration endpoint into an account-takeover primitive.
  """
  def registered_redirect_uri?(%__MODULE__{redirect_uris: uris}, uri) when is_binary(uri),
    do: uri in uris

  def registered_redirect_uri?(_client, _uri), do: false

  # An authorization code is delivered to these, so they must be addresses an attacker
  # cannot read: TLS everywhere, except loopback, which never leaves the machine and is how
  # every native client (Claude Code, Claude Desktop) receives its callback.
  #
  # Written against `get_field/2` rather than as `validate_change/3` callbacks: an empty
  # list equals the schema default, so `cast/3` records no change for it and every
  # change-driven validation would be skipped on exactly the input that must be refused.
  defp validate_redirect_uris(changeset) do
    case get_field(changeset, :redirect_uris) do
      uris when is_list(uris) and uris != [] -> check_redirect_uris(changeset, uris)
      _ -> add_error(changeset, :redirect_uris, "must list at least one redirect URI")
    end
  end

  defp check_redirect_uris(changeset, uris) when length(uris) > @max_redirect_uris,
    do: add_error(changeset, :redirect_uris, "must list at most #{@max_redirect_uris} URIs")

  defp check_redirect_uris(changeset, uris) do
    case Enum.find(uris, &(not valid_redirect_uri?(&1))) do
      nil -> changeset
      bad -> add_error(changeset, :redirect_uris, "is not acceptable: #{truncate(bad)}")
    end
  end

  defp valid_redirect_uri?(uri) when is_binary(uri) and byte_size(uri) <= @max_uri_length do
    case URI.parse(uri) do
      # A fragment is never sent to the server and cannot be matched, so it can only hide
      # something; reject rather than silently ignore it.
      %URI{fragment: fragment} when not is_nil(fragment) -> false
      %URI{scheme: "https", host: host} when is_binary(host) and host != "" -> true
      %URI{scheme: "http", host: host} -> loopback?(host)
      _ -> false
    end
  end

  defp valid_redirect_uri?(_uri), do: false

  defp loopback?(host), do: host in ["localhost", "127.0.0.1", "::1", "[::1]"]

  defp truncate(uri), do: String.slice(uri, 0, 80)
end
