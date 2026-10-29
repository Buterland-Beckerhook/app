defmodule Bbh.Repo.Migrations.AddAuthMethodToUsersTokens do
  use Ecto.Migration

  # How a session was established (passkey, magic_link, magic_link_totp). On the token
  # row, not in the cookie session: a session restored from the remember-me cookie
  # starts with an empty cookie session but the same token. Existing tokens stay NULL
  # and count as weak.
  def change do
    alter table(:users_tokens) do
      add :auth_method, :string
    end
  end
end
