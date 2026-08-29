defmodule Bbh.Repo.Migrations.CreateApiTokens do
  use Ecto.Migration

  # Bearer credentials for the MCP endpoint (see docs/adr/0009-mcp-server.md).
  #
  # Deliberately NOT `users_tokens`: `Accounts.update_user_and_delete_all_tokens/1` wipes
  # every row a user owns whenever their email is confirmed or changed, which would
  # silently kill a working integration. The extra columns (name, last_used_at,
  # revoked_at, audience) also have no business on the session-token schema.
  #
  # Shaped for the OAuth stage up front so adding it needs no second migration here:
  # `kind` separates personal access tokens from OAuth access/refresh tokens, `resource`
  # carries the RFC 8707 audience a token was minted for, `oauth_client_id` records which
  # registered client obtained it.

  def change do
    create table(:api_tokens, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false

      # SHA-256 of the token; the plaintext is shown to the caller exactly once and is
      # never recoverable from the database.
      add :token_hash, :binary, null: false

      add :kind, :string, null: false
      add :name, :string
      add :scopes, {:array, :string}, null: false, default: []
      add :resource, :string
      add :oauth_client_id, :string
      add :expires_at, :utc_datetime
      add :last_used_at, :utc_datetime
      add :revoked_at, :utc_datetime

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create unique_index(:api_tokens, [:token_hash])
    create index(:api_tokens, [:user_id])
    # Expiry lookups across all users. Note the pruning job ORs this against `revoked_at`,
    # which is unindexed, so that query seq-scans regardless — at a few thousand rows,
    # nightly, that is the cheaper trade than a second index.
    create index(:api_tokens, [:expires_at])

    create constraint(:api_tokens, :api_tokens_kind_valid,
             check: "kind IN ('pat', 'access', 'refresh')"
           )
  end
end
