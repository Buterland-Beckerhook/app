defmodule Bbh.ApiTokens.ApiToken do
  @moduledoc """
  A bearer credential for the MCP endpoint, owned by a user.

  Three kinds share the table:

    * `"pat"` — a personal access token minted in `/admin/einstellungen`. Long-lived,
      named, no audience (it is not tied to an OAuth client).
    * `"access"` / `"refresh"` — issued by the OAuth token endpoint. Short-lived, carry
      the `resource` they were minted for and the `oauth_client_id` that obtained them.

  Only the SHA-256 `token_hash` is stored; see `Bbh.ApiTokens` for the hashing and
  verification, which mirrors `Bbh.Accounts.UserToken`.
  """
  use Bbh.Schema

  @kinds ~w(pat access refresh)
  def kinds, do: @kinds

  @scopes ~w(mcp:read mcp:write)
  @doc "Every scope a token may carry. `mcp:write` does not imply `mcp:read`."
  def scopes, do: @scopes

  schema "api_tokens" do
    field :token_hash, :binary, redact: true
    field :kind, :string
    field :name, :string
    field :scopes, {:array, :string}, default: []
    field :resource, :string
    field :oauth_client_id, :string
    field :expires_at, :utc_datetime
    field :last_used_at, :utc_datetime
    field :revoked_at, :utc_datetime

    belongs_to :user, Bbh.Accounts.User

    timestamps(updated_at: false)
  end

  @doc false
  def changeset(token, attrs) do
    token
    |> cast(attrs, [
      :token_hash,
      :kind,
      :name,
      :scopes,
      :resource,
      :oauth_client_id,
      :expires_at,
      :user_id
    ])
    |> validate_required([:token_hash, :kind, :user_id])
    |> validate_inclusion(:kind, @kinds)
    |> validate_length(:name, max: 100)
    |> validate_scopes()
    |> unique_constraint(:token_hash)
    |> foreign_key_constraint(:user_id)
    |> check_constraint(:kind, name: :api_tokens_kind_valid)
  end

  defp validate_scopes(changeset) do
    validate_change(changeset, :scopes, fn :scopes, scopes ->
      if Enum.all?(scopes, &(&1 in @scopes)),
        do: [],
        else: [scopes: "enthält einen ungültigen Scope"]
    end)
  end

  @doc "Whether the token is currently usable (not revoked, not expired)."
  def active?(%__MODULE__{} = token, now \\ DateTime.utc_now()) do
    is_nil(token.revoked_at) and
      (is_nil(token.expires_at) or DateTime.after?(token.expires_at, now))
  end
end
