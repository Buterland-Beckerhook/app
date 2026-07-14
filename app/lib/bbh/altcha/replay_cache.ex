defmodule Bbh.Altcha.ReplayCache do
  @moduledoc """
  Short-TTL store of already-consumed Altcha challenges, used to reject replays
  of a valid proof-of-work solution. Backed by a public ETS table with a
  periodic sweep of expired entries. Single-node only (fine for the single
  container deploy).
  """
  use GenServer

  @table :altcha_replay_cache
  @sweep_interval :timer.minutes(1)

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @doc """
  Atomically marks `challenge` as used until `expires_at` (unix seconds).

  Returns `:ok` when the challenge had not been seen before, or `:error` when
  it is a replay.
  """
  def put_new(challenge, expires_at) when is_binary(challenge) and is_integer(expires_at) do
    if :ets.insert_new(@table, {challenge, expires_at}), do: :ok, else: :error
  end

  @impl true
  def init(_opts) do
    :ets.new(@table, [
      :named_table,
      :public,
      :set,
      read_concurrency: true,
      write_concurrency: true
    ])

    schedule_sweep()
    {:ok, %{}}
  end

  @impl true
  def handle_info(:sweep, state) do
    now = System.system_time(:second)
    :ets.select_delete(@table, [{{:_, :"$1"}, [{:<, :"$1", now}], [true]}])
    schedule_sweep()
    {:noreply, state}
  end

  defp schedule_sweep, do: Process.send_after(self(), :sweep, @sweep_interval)
end
