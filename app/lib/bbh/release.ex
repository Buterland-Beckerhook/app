defmodule Bbh.Release do
  @moduledoc """
  Used for executing DB release tasks when run in production without Mix
  installed.
  """
  @app :bbh

  def migrate do
    load_app()

    for repo <- repos() do
      {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
    end
  end

  def rollback(repo, version) do
    load_app()
    {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :down, to: version))
  end

  @doc """
  Re-encrypts every Postfach value with the current key (`TICKET_KEY_CURRENT`) — the
  second half of a key rotation. Afterwards the old key can leave `TICKET_KEYS`.

      bin/bbh eval "Bbh.Release.rekey_tickets()"

  Row by row, so it is safe to rerun after an interruption; values already on the
  current key are skipped. Raises on a value that does not decrypt, before the old key
  is gone.
  """
  def rekey_tickets do
    load_app()
    Bbh.Vault.check!()

    # Only the repo, not the app: the running release already holds the endpoint's port.
    {:ok, counts, _} =
      Ecto.Migrator.with_repo(Bbh.Repo, fn _repo ->
        for {table, columns} <- [
              {"tickets", ~w(subject_enc requester_name_enc requester_email_enc payload_enc)},
              {"ticket_messages", ~w(from_enc to_enc body_enc)},
              {"ticket_attachments", ~w(filename_enc data_enc)}
            ],
            into: %{} do
          {table, rekey_table(table, columns)}
        end
      end)

    IO.puts("Re-encrypted: #{inspect(counts)}")
    counts
  end

  defp rekey_table(table, columns) do
    import Ecto.Query

    fields = Enum.map(columns, &String.to_existing_atom/1)
    ids = Bbh.Repo.all(from r in table, select: type(r.id, :binary_id))

    Enum.reduce(ids, 0, fn id, count ->
      row = from(r in table, where: r.id == type(^id, :binary_id))
      values = Bbh.Repo.one!(select(row, [r], map(r, ^fields)))

      changes =
        Enum.flat_map(fields, fn field ->
          case Bbh.Vault.rekey(values[field], Bbh.Vault.aad(table, field, id)) do
            {:ok, new} -> [{field, new}]
            :unchanged -> []
            :error -> raise "#{table}.#{field} of #{id} does not decrypt — keep the old key"
          end
        end)

      if changes == [] do
        count
      else
        Bbh.Repo.update_all(row, set: changes)
        count + 1
      end
    end)
  end

  defp repos do
    Application.fetch_env!(@app, :ecto_repos)
  end

  defp load_app do
    # Many platforms require SSL when connecting to the database
    Application.ensure_all_started(:ssl)
    Application.ensure_loaded(@app)
  end
end
