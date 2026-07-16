defmodule Bbh.Accounts.UserPasskey do
  @moduledoc "A WebAuthn passkey (public-key credential) belonging to a user."
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "users_passkeys" do
    field :credential_id, :binary
    field :public_key, Bbh.Accounts.CoseKey
    field :aaguid, :binary
    field :sign_count, :integer, default: 0
    field :nickname, :string
    field :last_used_at, :utc_datetime
    belongs_to :user, Bbh.Accounts.User

    timestamps(type: :utc_datetime)
  end

  @doc "Changeset for storing a freshly registered passkey."
  def changeset(passkey, attrs) do
    passkey
    |> cast(attrs, [:credential_id, :public_key, :aaguid, :sign_count, :nickname, :user_id])
    |> validate_required([:credential_id, :public_key, :sign_count, :nickname, :user_id])
    |> validate_length(:nickname, min: 1, max: 60)
    |> unique_constraint(:credential_id)
  end
end
