defmodule Bbh.Repo.Migrations.CreateOauthTables do
  use Ecto.Migration

  # The OAuth 2.1 authorization server that lets the Claude app connect to /mcp.
  # See docs/adr/0010-mcp-oauth.md.
  #
  # Public clients only — every client registers dynamically (RFC 7591) and authenticates
  # with PKCE, so there is no client secret column to protect. `api_tokens` already carries
  # `resource` and `oauth_client_id` (added in the MCP migration), which is where the
  # issued access and refresh tokens live; only the client registry and the short-lived
  # authorization codes are new here.

  def change do
    create table(:oauth_clients, primary_key: false) do
      add :id, :binary_id, primary_key: true
      # The public identifier handed to the client. Random, not guessable, and the value
      # `api_tokens.oauth_client_id` stores.
      add :client_id, :string, null: false
      add :client_name, :string
      add :redirect_uris, {:array, :string}, null: false, default: []
      add :grant_types, {:array, :string}, null: false, default: []
      add :scopes, {:array, :string}, null: false, default: []

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create unique_index(:oauth_clients, [:client_id])

    create table(:oauth_codes, primary_key: false) do
      add :id, :binary_id, primary_key: true
      # Hashed like every other credential here: a code is a bearer value until redeemed.
      add :code_hash, :binary, null: false
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false

      # The string `client_id`, not a foreign key to `oauth_clients.id` — deliberately the
      # same shape as `api_tokens.oauth_client_id`, so both tables are queried the same way.
      add :client_id, :string, null: false

      # Bound at issue time and re-checked at redemption: all three must match the token
      # request or the code is refused (RFC 8707 audience + PKCE + exact redirect match).
      add :redirect_uri, :string, null: false
      add :code_challenge, :string, null: false
      add :resource, :string, null: false
      add :scopes, {:array, :string}, null: false, default: []

      add :expires_at, :utc_datetime, null: false
      # Set on redemption. A code is single-use; a second attempt is an attack signal.
      add :used_at, :utc_datetime

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create unique_index(:oauth_codes, [:code_hash])
    create index(:oauth_codes, [:user_id])
    create index(:oauth_codes, [:expires_at])

    create index(:api_tokens, [:oauth_client_id])
  end
end
