defmodule Bbh.Accounts.Postfach do
  @moduledoc """
  A user's Postfach side, stored with the account: the queues they are granted
  (`Bbh.Accounts.QueueGrant`) and their notification settings (fields on `users`). What
  a queue is, and how notifications go out, is `Bbh.Tickets`' business.
  """
  import Ecto.Query, warn: false

  alias Bbh.Accounts.{QueueGrant, User}
  alias Bbh.Repo

  ## Postfach queue grants (`Bbh.Accounts.QueueGrant`)
  #
  # Only the storage: whether a key names a queue, the order queues are shown in and the
  # audit event are `Bbh.Tickets.Grants`' business.

  @doc "The queue keys `user` is granted, unordered."
  def list_queue_keys(%User{id: user_id}),
    do: Repo.all(from g in QueueGrant, where: g.user_id == ^user_id, select: g.queue_key)

  def list_queue_keys(_), do: []

  @doc "`%{user_id => [queue_key]}` for all users."
  def queue_grants_by_user do
    Repo.all(from g in QueueGrant, select: {g.user_id, g.queue_key})
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
  end

  @doc "`%{queue_key => [user_id]}` for the given queues; a queue nobody holds is missing."
  def queue_user_ids(queue_keys) do
    Repo.all(
      from g in QueueGrant, where: g.queue_key in ^queue_keys, select: {g.queue_key, g.user_id}
    )
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
  end

  @doc "The users granted `queue_key` (not admins without a grant), by email."
  def list_queue_users(queue_key) do
    Repo.all(
      from u in User,
        join: g in QueueGrant,
        on: g.user_id == u.id,
        where: g.queue_key == ^queue_key,
        order_by: u.email
    )
  end

  @doc "Whether anyone holds a grant for `queue_key`."
  def queue_granted?(queue_key),
    do: Repo.exists?(from g in QueueGrant, where: g.queue_key == ^queue_key)

  @doc """
  Replaces `user`'s grants with `keys` (already checked by the caller), recording `admin`
  as the granting user, in one transaction. Returns `{:ok, changed?}`.
  """
  def replace_queue_grants(%User{} = admin, %User{} = user, keys) do
    now = DateTime.utc_now(:second)

    Repo.transact(fn ->
      current = list_queue_keys(user)

      Repo.delete_all(
        from g in QueueGrant, where: g.user_id == ^user.id and g.queue_key not in ^keys
      )

      rows =
        for key <- keys,
            key not in current,
            do: %{
              id: Ecto.UUID.generate(),
              user_id: user.id,
              queue_key: key,
              granted_by_id: admin.id,
              inserted_at: now
            }

      Repo.insert_all(QueueGrant, rows)
      {:ok, Enum.sort(current) != Enum.sort(keys)}
    end)
  end

  ## Postfach notification settings (the fields live on the user)

  @doc "A changeset for the user's Postfach notification settings."
  def change_ticket_notifications(%User{} = user, attrs \\ %{}),
    do: User.ticket_notifications_changeset(user, attrs)

  @doc "Saves the user's Postfach notification settings."
  def update_ticket_notifications(%User{} = user, attrs),
    do: user |> change_ticket_notifications(attrs) |> Repo.update()

  @doc """
  Marks that the user got today's Postfach reminders; `false` if they already had. One
  conditional `UPDATE`, so of two overlapping runs only one reminds.
  """
  def claim_ticket_reminder(%User{id: id}, %Date{} = today) do
    {count, _} =
      Repo.update_all(
        from(u in User,
          where: u.id == ^id and (is_nil(u.ticket_reminded_on) or u.ticket_reminded_on < ^today)
        ),
        set: [ticket_reminded_on: today]
      )

    count > 0
  end
end
