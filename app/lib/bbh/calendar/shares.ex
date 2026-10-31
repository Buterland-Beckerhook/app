defmodule Bbh.Calendar.Shares do
  @moduledoc """
  Calendar shares: revocable per-recipient links to one internal calendar's iCal feed.
  Only a hash of each token is stored; the plaintext exists once, in the share URL.
  """
  import Ecto.Query
  alias Bbh.Repo
  alias Bbh.Calendar.{CalendarShare, Event}

  @doc """
  Creates a share for an internal `calendar` and returns `{:ok, {plaintext, share}}`.

  The plaintext token is only available here (never re-derivable from the stored
  hash) — hand it to the recipient via the share URL. `created_by` is the granting
  user (or `nil`). `attrs` may carry `:recipient_label` and `:expires_at`.
  """
  def create_share(calendar, attrs, created_by) do
    {plaintext, hash} = CalendarShare.build_token()

    params =
      attrs
      |> Map.new()
      |> Map.merge(%{
        calendar: calendar,
        token: hash,
        created_by_id: created_by && created_by.id
      })

    case %CalendarShare{} |> CalendarShare.changeset(params) |> Repo.insert() do
      {:ok, share} -> {:ok, {plaintext, share}}
      {:error, changeset} -> {:error, changeset}
    end
  end

  @doc """
  Shares for one internal calendar, or for a list of calendars, newest first.
  """
  def list_shares(calendars) when is_list(calendars) do
    Repo.all(
      from s in CalendarShare, where: s.calendar in ^calendars, order_by: [desc: s.inserted_at]
    )
  end

  def list_shares(calendar) do
    Repo.all(
      from s in CalendarShare, where: s.calendar == ^calendar, order_by: [desc: s.inserted_at]
    )
  end

  @doc """
  Mints a fresh token for an existing share, returning `{:ok, {plaintext, share}}`.

  The previous link stops working immediately (only the new hash is stored). Used
  by "resend": the recipient/calendar/expiry are kept, `last_used_at` is cleared.
  """
  def rotate_share_token(%CalendarShare{} = share) do
    {plaintext, hash} = CalendarShare.build_token()

    case share
         |> Ecto.Changeset.change(token: hash, last_used_at: nil)
         |> Ecto.Changeset.unique_constraint(:token)
         |> Repo.update() do
      {:ok, share} -> {:ok, {plaintext, share}}
      {:error, changeset} -> {:error, changeset}
    end
  end

  @doc "Revokes a share by id. Idempotent — keeps the original revocation time."
  def revoke_share(id) do
    share = Repo.get!(CalendarShare, id)

    if share.revoked_at do
      {:ok, share}
    else
      share |> Ecto.Changeset.change(revoked_at: Bbh.Time.now()) |> Repo.update()
    end
  end

  @doc """
  Resolves a plaintext share token to its share, or `:error`.

  Rejects revoked, expired, unknown and malformed tokens. On success the share's
  `last_used_at` is stamped.
  """
  def verify_share_token(plaintext) do
    with {:ok, hash} <- CalendarShare.hash_token(plaintext),
         %CalendarShare{} = share <- Repo.get_by(CalendarShare, token: hash),
         true <- CalendarShare.active?(share),
         {:ok, share} <-
           share |> Ecto.Changeset.change(last_used_at: Bbh.Time.now()) |> Repo.update() do
      {:ok, share}
    else
      _ -> :error
    end
  end

  @doc """
  Published events of one internal calendar, chronological — the read model behind
  a share's iCal feed. Deliberately separate from the public `is_nil(calendar)`
  gate so sharing never widens what counts as public.
  """
  def shared_calendar_events(calendar) do
    Repo.all(
      from e in Event,
        where: e.calendar == ^calendar and e.status == "published",
        order_by: [asc: e.starts_at],
        preload: [:location]
    )
  end

  @doc """
  Emails the share link to `share.recipient_label` when it looks like an address.

  Returns `{:ok, email}`, `{:error, reason}` from the mailer, or `:skip` when the
  label is not an email.
  """
  def deliver_share_link(%CalendarShare{recipient_label: label} = share, webcal_url, https_url) do
    if CalendarShare.emailable?(share) do
      Bbh.Calendar.ShareNotifier.deliver_calendar_share_instructions(
        label,
        Event.calendar_label(share.calendar),
        webcal_url,
        https_url
      )
    else
      :skip
    end
  end
end
