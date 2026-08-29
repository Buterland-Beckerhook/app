defmodule Bbh.OAuth.AuthorizationCode do
  @moduledoc """
  A single-use authorization code, issued by the consent screen and redeemed at the token
  endpoint.

  Everything the token request must prove is frozen onto the row at issue time — the
  client, the exact redirect URI, the PKCE challenge, the requested audience and scopes —
  so redemption is a comparison against what the user actually approved rather than
  against what the client re-sends.

  Only the SHA-256 of the code is stored. It travels through a browser redirect and a
  query string, which is precisely why it is short-lived and may be spent once.
  """
  use Bbh.Schema

  alias Bbh.ApiTokens.ApiToken

  schema "oauth_codes" do
    field :code_hash, :binary, redact: true
    field :client_id, :string
    field :redirect_uri, :string
    field :code_challenge, :string, redact: true
    field :resource, :string
    field :scopes, {:array, :string}, default: []
    field :expires_at, :utc_datetime
    field :used_at, :utc_datetime

    belongs_to :user, Bbh.Accounts.User

    timestamps(updated_at: false)
  end

  @doc false
  def changeset(code, attrs) do
    code
    |> cast(attrs, [
      :code_hash,
      :client_id,
      :redirect_uri,
      :code_challenge,
      :resource,
      :scopes,
      :expires_at,
      :user_id
    ])
    |> validate_required([
      :code_hash,
      :client_id,
      :redirect_uri,
      :code_challenge,
      :resource,
      :expires_at,
      :user_id
    ])
    |> validate_subset(:scopes, ApiToken.scopes())
    |> unique_constraint(:code_hash)
    |> foreign_key_constraint(:user_id)
  end

  @doc "Whether the code may still be redeemed: not yet spent, not yet expired."
  def redeemable?(%__MODULE__{} = code, now \\ DateTime.utc_now()) do
    is_nil(code.used_at) and DateTime.after?(code.expires_at, now)
  end
end
