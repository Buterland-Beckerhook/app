defmodule Bbh.Calendar.CalendarShare do
  @moduledoc """
  A revocable share of one internal calendar with one recipient.

  The plaintext token is generated once and handed to the recipient inside the
  share URL; only its SHA-256 hash is stored (same scheme as
  `Bbh.Accounts.UserToken`), so read access to the database never yields a
  usable token. A share is disabled by setting `revoked_at`, or expires once
  `expires_at` has passed (both optional — `expires_at` nil means no expiry).
  """
  use Bbh.Schema

  alias Bbh.Calendar.Event

  @hash_algorithm :sha256
  @rand_size 32

  schema "calendar_shares" do
    field :calendar, :string
    field :token, :binary
    field :recipient_label, :string
    field :revoked_at, :utc_datetime
    field :last_used_at, :utc_datetime
    field :expires_at, :utc_datetime

    belongs_to :created_by, Bbh.Accounts.User

    timestamps()
  end

  @doc """
  Generates a random share token, returning `{plaintext, hash}`.

  The URL-safe `plaintext` goes to the recipient; the `hash` is what
  `changeset/2` should persist in `:token`.
  """
  def build_token do
    raw = :crypto.strong_rand_bytes(@rand_size)
    {Base.url_encode64(raw, padding: false), :crypto.hash(@hash_algorithm, raw)}
  end

  @doc "Hashes a plaintext token for lookup, or `:error` if it can't be decoded."
  def hash_token(plaintext) do
    case Base.url_decode64(plaintext, padding: false) do
      {:ok, raw} -> {:ok, :crypto.hash(@hash_algorithm, raw)}
      :error -> :error
    end
  end

  @doc false
  def changeset(share, attrs) do
    share
    |> cast(attrs, [:calendar, :token, :recipient_label, :expires_at, :created_by_id])
    |> validate_required([:calendar, :token])
    |> validate_inclusion(:calendar, Event.calendars(), message: "ist kein gültiger Kalender")
    |> unique_constraint(:token)
    |> foreign_key_constraint(:created_by_id)
  end

  @doc "Whether the share has been revoked."
  def revoked?(%__MODULE__{revoked_at: revoked_at}), do: not is_nil(revoked_at)

  @doc "Whether the share has an expiry that is now in the past."
  def expired?(%__MODULE__{expires_at: nil}, _now), do: false

  def expired?(%__MODULE__{expires_at: expires_at}, now),
    do: DateTime.compare(expires_at, now) != :gt

  @doc "Whether the share is currently usable (neither revoked nor expired)."
  def active?(%__MODULE__{} = share, now \\ Bbh.Time.now()),
    do: not revoked?(share) and not expired?(share, now)

  @doc "Whether the recipient label looks like an email address we can deliver to."
  def emailable?(%__MODULE__{recipient_label: label}), do: emailable?(label)
  def emailable?(label) when is_binary(label), do: label =~ ~r/^[^@\s]+@[^@\s]+\.[^@\s]+$/
  def emailable?(_), do: false
end
