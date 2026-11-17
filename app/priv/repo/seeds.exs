# Dev-admin bootstrap for a from-scratch database.
#
# Real dev data comes from a snapshot restore (`make seed`), not from here.
# This only ensures a login exists on an otherwise empty DB.
# Run with: mix run priv/repo/seeds.exs  (safe to re-run; no-ops if a user exists)
#
# There are no passwords: sign-in is a magic link (plus TOTP) or a passkey. In dev the
# link lands in the Swoosh mailbox preview; an admin is then asked to set up a second
# factor before the strong-auth areas open.

alias Bbh.Repo
alias Bbh.Accounts.User

email = "admin@buterland-beckerhook.de"

if Repo.aggregate(User, :count) == 0 do
  %User{}
  |> User.email_changeset(%{email: email})
  |> Ecto.Changeset.put_change(:role, "admin")
  |> Ecto.Changeset.put_change(:confirmed_at, DateTime.utc_now(:second))
  |> Repo.insert!()

  IO.puts("""
  Created dev admin #{email}.
  Sign in at https://localhost/users/log-in with that address; the magic link
  shows up at https://localhost/dev/mailbox.
  """)
else
  IO.puts("User already present, skipping dev admin.")
end
