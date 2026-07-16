# Dev-admin bootstrap for a from-scratch database.
#
# Real dev data comes from a snapshot restore (`make seed`), not from here.
# This only ensures a login exists on an otherwise empty DB.
# Run with: mix run priv/repo/seeds.exs  (safe to re-run; no-ops if a user exists)

alias Bbh.Repo
alias Bbh.Accounts.User

# Dev admin (change the password after first login).
if Repo.aggregate(User, :count) == 0 do
  %User{}
  |> User.email_changeset(%{email: "admin@buterland-beckerhook.de"})
  |> User.password_changeset(%{password: "change-me-please-1234"})
  |> Ecto.Changeset.put_change(:role, "admin")
  |> Ecto.Changeset.put_change(:confirmed_at, DateTime.utc_now(:second))
  |> Repo.insert!()

  IO.puts("Created dev admin admin@buterland-beckerhook.de / change-me-please-1234")
else
  IO.puts("User already present, skipping dev admin.")
end
