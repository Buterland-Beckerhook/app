defmodule Bbh.Accounts.User do
  use Ecto.Schema
  import Ecto.Changeset

  @roles ~w(admin editor calendar_editor)
  def roles, do: @roles

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "users" do
    field :email, :string
    field :confirmed_at, :utc_datetime
    field :authenticated_at, :utc_datetime, virtual: true
    field :role, :string, default: "editor"
    field :calendars, {:array, :string}, default: []
    field :totp_secret, :binary, redact: true
    field :totp_confirmed_at, :utc_datetime

    timestamps(type: :utc_datetime)
  end

  @doc "Whether the user is an administrator."
  def admin?(%__MODULE__{role: "admin"}), do: true
  def admin?(_), do: false

  @doc "Whether the user is a calendar-only editor."
  def calendar_editor?(%__MODULE__{role: "calendar_editor"}), do: true
  def calendar_editor?(_), do: false

  @doc "Whether the user has been granted a specific (non-public) calendar."
  def manages_calendar?(%__MODULE__{calendars: cals}, calendar) when is_binary(calendar),
    do: calendar in (cals || [])

  def manages_calendar?(_, _), do: false

  @doc "Whether the user has enabled a TOTP second factor."
  def totp_enabled?(%__MODULE__{totp_confirmed_at: nil}), do: false
  def totp_enabled?(%__MODULE__{}), do: true

  @doc "Changeset for an admin to set a user's role."
  def role_changeset(user, attrs) do
    user
    |> cast(attrs, [:role])
    |> validate_required([:role])
    |> validate_inclusion(:role, @roles)
    |> check_constraint(:role, name: :users_role_valid, message: "ist keine gültige Rolle")
  end

  @doc "Changeset for an admin to assign which (non-public) calendars a user may manage."
  def calendars_changeset(user, attrs) do
    user
    |> cast(attrs, [:calendars])
    |> update_change(:calendars, fn cals -> Enum.reject(cals || [], &(&1 in [nil, ""])) end)
    |> validate_calendars()
  end

  defp validate_calendars(changeset) do
    valid = Bbh.Calendar.Event.calendars()

    validate_change(changeset, :calendars, fn :calendars, cals ->
      if Enum.all?(cals, &(&1 in valid)),
        do: [],
        else: [calendars: "enthält einen ungültigen Kalender"]
    end)
  end

  @doc """
  A user changeset for registering or changing the email.

  It requires the email to change otherwise an error is added.

  ## Options

    * `:validate_unique` - Set to false if you don't want to validate the
      uniqueness of the email, useful when displaying live validations.
      Defaults to `true`.
  """
  def email_changeset(user, attrs, opts \\ []) do
    user
    |> cast(attrs, [:email])
    |> validate_email(opts)
  end

  defp validate_email(changeset, opts) do
    changeset =
      changeset
      |> validate_required([:email])
      |> validate_format(:email, ~r/^[^@,;\s]+@[^@,;\s]+$/,
        message: "must have the @ sign and no spaces"
      )
      |> validate_length(:email, max: 160)

    if Keyword.get(opts, :validate_unique, true) do
      changeset
      |> unsafe_validate_unique(:email, Bbh.Repo)
      |> unique_constraint(:email)
      |> validate_email_changed()
    else
      changeset
    end
  end

  defp validate_email_changed(changeset) do
    if get_field(changeset, :email) && get_change(changeset, :email) == nil do
      add_error(changeset, :email, "did not change")
    else
      changeset
    end
  end

  @doc """
  Confirms the account by setting `confirmed_at`.
  """
  def confirm_changeset(user) do
    now = DateTime.utc_now(:second)
    change(user, confirmed_at: now)
  end
end
