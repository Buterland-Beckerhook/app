defmodule Bbh.Repo do
  use Ecto.Repo,
    otp_app: :bbh,
    adapter: Ecto.Adapters.Postgres
end
