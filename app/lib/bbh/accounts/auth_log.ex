defmodule Bbh.Accounts.AuthLog do
  @moduledoc """
  Login log for the admin area: who signed in when, how, and from where — and the
  attempts that failed. Admins read it per user (`/admin/benutzer/:id/anmeldungen`) to
  spot a stolen login link or a guessed account.

  Purpose is the security of the admin area (Datenschutzerklärung); entries are pruned by
  `Bbh.Workers.AuthPruner` after `AUTH_LOG_RETENTION_DAYS` (default 90). Attempts that
  name no known account are kept without a user, and the address typed in is not stored.

  Writing an entry never fails the login it describes: errors are logged and dropped.
  """
  import Ecto.Query

  require Logger

  alias Bbh.Accounts.{AuthEvent, User}
  alias Bbh.Repo

  @doc """
  Records an event. `attrs`: `:user` (or nil), `:event`, `:method`, `:ip`, `:user_agent`.
  """
  def record(attrs) do
    user_id =
      case attrs[:user] do
        %User{id: id} -> id
        _ -> nil
      end

    attrs = attrs |> Map.new() |> Map.delete(:user) |> Map.put(:user_id, user_id)

    case %AuthEvent{} |> AuthEvent.changeset(attrs) |> Repo.insert() do
      {:ok, event} ->
        {:ok, event}

      {:error, changeset} ->
        Logger.warning("Auth event not recorded: #{inspect(changeset.errors)}")
        :error
    end
  rescue
    e ->
      Logger.warning("Auth event not recorded: #{Exception.message(e)}")
      :error
  end

  @doc "A user's entries within the retention period, newest first."
  def list_for_user(%User{id: user_id}, limit \\ 500) do
    Repo.all(
      from e in AuthEvent,
        where: e.user_id == ^user_id and e.inserted_at > ^cutoff(retention_days()),
        order_by: [desc: e.inserted_at, desc: e.id],
        limit: ^limit
    )
  end

  @doc "Deletes entries older than `days`; returns the count."
  def prune(days \\ retention_days()) do
    {count, _} = Repo.delete_all(from e in AuthEvent, where: e.inserted_at < ^cutoff(days))
    count
  end

  @doc "Days an entry is kept (`AUTH_LOG_RETENTION_DAYS`)."
  def retention_days, do: Application.get_env(:bbh, :auth_log_retention_days, 90)

  defp cutoff(days), do: DateTime.utc_now(:second) |> DateTime.add(-days, :day)
end
