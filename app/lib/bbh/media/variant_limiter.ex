defmodule Bbh.Media.VariantLimiter do
  @moduledoc """
  A counting semaphore that bounds how many libvips variant generations run at
  once. Without it, opening the media library or picker fires one HTTP request
  per image, each triggering a native image decode — a cold-cache "thundering
  herd" that piles up native (non-BEAM-tracked) memory and, before the deploy
  memory limit existed, took down the whole host.

  `run/1` executes the given fun while holding one of `@max` permits, blocking
  until a permit frees. Permit holders are monitored, so a crashing caller can
  never leak a permit. If the limiter isn't running (e.g. a unit test that skips
  the supervision tree), `run/1` degrades to executing the fun directly.
  """
  use GenServer

  # Deliberately small: variant generation is CPU/memory heavy and, with
  # shrink-on-load, individually cheap — we only need to stop a burst.
  @max 2

  def start_link(opts) do
    max = Keyword.get(opts, :max, @max)
    GenServer.start_link(__MODULE__, max, name: __MODULE__)
  end

  @doc "Run `fun` holding one permit. Blocks until a permit is available."
  def run(fun) when is_function(fun, 0) do
    case acquire() do
      :ok ->
        try do
          fun.()
        after
          GenServer.cast(__MODULE__, {:release, self()})
        end

      # Limiter not started — better to do the work than to fail the request.
      :unavailable ->
        fun.()
    end
  end

  defp acquire do
    GenServer.call(__MODULE__, :acquire, :infinity)
  catch
    :exit, _ -> :unavailable
  end

  @impl true
  def init(max) do
    {:ok, %{max: max, count: 0, waiters: :queue.new(), holders: %{}}}
  end

  @impl true
  def handle_call(:acquire, {pid, _tag} = from, state) do
    if state.count < state.max do
      {:noreply, grant(state, pid, from)}
    else
      {:noreply, %{state | waiters: :queue.in(from, state.waiters)}}
    end
  end

  @impl true
  def handle_cast({:release, pid}, state), do: {:noreply, release(state, pid)}

  @impl true
  def handle_info({:DOWN, _ref, :process, pid, _reason}, state),
    do: {:noreply, release(state, pid)}

  # Reply :ok to the caller, monitor it, and record the permit.
  defp grant(state, pid, from) do
    ref = Process.monitor(pid)
    GenServer.reply(from, :ok)
    %{state | count: state.count + 1, holders: Map.put(state.holders, pid, ref)}
  end

  # Release a permit (explicit release or holder death), then hand it to the
  # next waiter if any.
  defp release(state, pid) do
    case Map.pop(state.holders, pid) do
      {nil, _holders} ->
        state

      {ref, holders} ->
        Process.demonitor(ref, [:flush])
        state = %{state | count: state.count - 1, holders: holders}

        case :queue.out(state.waiters) do
          {{:value, {wpid, _tag} = from}, rest} ->
            grant(%{state | waiters: rest}, wpid, from)

          {:empty, _} ->
            state
        end
    end
  end
end
