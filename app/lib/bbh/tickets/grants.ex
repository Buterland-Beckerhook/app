defmodule Bbh.Tickets.Grants do
  @moduledoc """
  Which users work which Postfach queue. Set by admins in the user administration,
  independent of the content role; admins read every queue without a grant.

  The grants themselves are stored with the accounts (`Bbh.Accounts.QueueGrant`): a
  grant is a permission of the user, and `Bbh.Accounts.Scope` loads them without
  reaching back into the Postfach. This module adds what only the Postfach knows — which
  keys name a queue, the order they are shown in, and who hears about a queue nobody
  is granted.

  Grants are their own table rather than an array on `users` (like `users.calendars`) so
  that "who handles queue X" is one indexed query and every grant records who gave it.
  """
  alias Bbh.Accounts
  alias Bbh.Accounts.User
  alias Bbh.Tickets.Queue

  @doc "The queue keys a user is granted, in queue order."
  def list_queue_keys(user) do
    granted = Accounts.Postfach.list_queue_keys(user)
    Enum.filter(Queue.keys(), &(&1 in granted))
  end

  @doc "`%{user_id => [queue_key]}` for all users, for the user administration."
  defdelegate grants_by_user, to: Accounts.Postfach, as: :queue_grants_by_user

  @doc "The users granted a queue (not admins without a grant)."
  defdelegate list_users(queue_key), to: Accounts.Postfach, as: :list_queue_users

  @doc """
  Who hears about a queue's tickets: the users granted it — or, while nobody is, the
  admins, so a request to an unstaffed queue is never announced to no one.
  """
  def notify_users(queue_key) do
    case list_users(queue_key) do
      [] -> Accounts.list_admins()
      users -> users
    end
  end

  @doc """
  `notify_users/1` for several queues at once, as ids: `%{queue_key => [user_id]}`. At
  most two queries however many queues, for the workers that resolve a whole batch of
  tickets.
  """
  def notify_user_ids([]), do: %{}

  def notify_user_ids(queue_keys) do
    keys = Enum.uniq(queue_keys)
    granted = Accounts.Postfach.queue_user_ids(keys)

    admins =
      if Enum.all?(keys, &Map.has_key?(granted, &1)),
        do: [],
        else: Enum.map(Accounts.list_admins(), & &1.id)

    Map.new(keys, &{&1, Map.get(granted, &1, admins)})
  end

  @doc """
  Replaces a user's grants with `keys`, in one transaction. `admin` is recorded as the
  granting user. Unknown keys are refused.
  """
  def set_grants(%User{} = admin, %User{} = user, keys) do
    keys = keys |> Enum.reject(&(&1 in [nil, ""])) |> Enum.uniq()

    if Enum.all?(keys, &Queue.valid?/1) do
      {:ok, changed?} = Accounts.Postfach.replace_queue_grants(admin, user, keys)

      if changed? do
        Bbh.Tickets.log_event(nil, admin, "grants_changed", %{user_id: user.id, queues: keys})
      end

      {:ok, list_queue_keys(user)}
    else
      {:error, :invalid_queue}
    end
  end
end
