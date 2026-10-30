defmodule Bbh.Accounts.AuthEvent do
  @moduledoc "One entry of the login log — see `Bbh.Accounts.AuthLog`."
  use Ecto.Schema
  import Ecto.Changeset

  @events ~w(magic_link_sent login_succeeded login_failed totp_failed passkey_failed logged_out
              factors_reset factor_reset_failed)

  @doc "The events the log knows."
  def events, do: @events

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "auth_events" do
    belongs_to :user, Bbh.Accounts.User
    field :event, :string
    field :method, :string
    field :ip, :string
    field :user_agent, :string

    timestamps(type: :utc_datetime, updated_at: false)
  end

  @doc false
  def changeset(event, attrs) do
    event
    |> cast(attrs, [:user_id, :event, :method, :ip, :user_agent])
    |> update_change(:user_agent, &String.slice(&1, 0, 255))
    |> validate_required([:event])
    |> validate_inclusion(:event, @events)
    |> validate_inclusion(:method, Bbh.Accounts.User.auth_methods())
  end
end
