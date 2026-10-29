defmodule Bbh.Tickets.Grants do
  @moduledoc """
  Which users work which Postfach queue. Set by admins in the user administration,
  independent of the content role; admins read every queue without a grant.

  Grants are their own table rather than an array on `users` (like `users.calendars`) so
  that "who handles queue X" is one indexed query and every grant records who gave it.
  """
  import Ecto.Query

  require Logger

  alias Bbh.Accounts.User
  alias Bbh.Repo
  alias Bbh.Tickets.{Grant, Queue}

  @doc "The queue keys a user is granted, in queue order."
  def list_queue_keys(%User{id: user_id}) do
    granted =
      Repo.all(from g in Grant, where: g.user_id == ^user_id, select: g.queue_key)

    Enum.filter(Queue.keys(), &(&1 in granted))
  end

  def list_queue_keys(_), do: []

  @doc "`%{user_id => [queue_key]}` for all users, for the user administration."
  def grants_by_user do
    Repo.all(from g in Grant, select: {g.user_id, g.queue_key})
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
  end

  @doc "The users granted a queue (not admins without a grant)."
  def list_users(queue_key) do
    Repo.all(
      from u in User,
        join: g in Grant,
        on: g.user_id == u.id,
        where: g.queue_key == ^queue_key,
        order_by: u.email
    )
  end

  @doc """
  Replaces a user's grants with `keys`, in one transaction. `admin` is recorded as the
  granting user. Unknown keys are refused.
  """
  def set_grants(%User{} = admin, %User{} = user, keys) do
    keys = keys |> Enum.reject(&(&1 in [nil, ""])) |> Enum.uniq()

    if Enum.all?(keys, &Queue.valid?/1) do
      now = DateTime.utc_now(:second)

      Repo.transact(fn ->
        current = list_queue_keys(user)

        Repo.delete_all(
          from g in Grant, where: g.user_id == ^user.id and g.queue_key not in ^keys
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

        Repo.insert_all(Grant, rows)

        if Enum.sort(current) != Enum.sort(keys) do
          Logger.info("Postfach grants of user #{user.id} set to #{inspect(keys)} by #{admin.id}")
        end

        {:ok, list_queue_keys(user)}
      end)
    else
      {:error, :invalid_queue}
    end
  end
end
