defmodule Bbh.Blz do
  @moduledoc """
  In-memory BLZ → {BIC, bank name} lookup, used to derive BIC/Kreditinstitut from a
  German IBAN on the membership form.

  The table is the stripped Bundesbank "Bankleitzahlendatei" (see
  `mix bbh.blz.strip`). It is loaded once at boot into `:persistent_term` — a few
  thousand read-only entries, no per-lookup process hop, no GC churn.

  Everything degrades gracefully: if no data file is found (or it is outdated and a
  BLZ is missing), lookups simply return `:error` and the caller leaves the fields
  blank. The file is resolved in this order, first hit wins:

    1. `BLZ_DATA_FILE` env var (an absolute path), if set and present.
    2. `/data/blz.tsv` — a drop-in in the mounted data volume, refreshable without a
       rebuild (same spirit as uploads/dumps).
    3. `priv/data/blz.tsv` — the copy shipped in the release.
  """
  use GenServer

  require Logger

  @pt_key {__MODULE__, :map}

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @doc """
  Look up `{:ok, %{bic: bic, name: name}}` for a German IBAN, or `:error` when the
  IBAN is not a resolvable DE IBAN or its BLZ is not in the table.
  """
  def lookup_by_iban(iban) do
    normalized = iban |> to_string() |> String.upcase() |> String.replace(~r/\s/, "")

    with <<"DE", _check::binary-size(2), blz::binary-size(8), _rest::binary>> <- normalized,
         {bic, name} when is_binary(bic) <- Map.get(table(), blz) do
      {:ok, %{bic: bic, name: name}}
    else
      _ -> :error
    end
  end

  @doc "Number of loaded entries (0 when no data file was found). Handy for diagnostics."
  def size, do: map_size(table())

  @impl true
  def init(_opts) do
    map = load()

    case map_size(map) do
      0 -> Logger.warning("[blz] no BLZ data file found — IBAN→BIC derivation disabled")
      n -> Logger.info("[blz] loaded #{n} BLZ entries from #{source() || "?"}")
    end

    :persistent_term.put(@pt_key, map)
    {:ok, %{}}
  end

  defp table, do: :persistent_term.get(@pt_key, %{})

  # The path is operator-controlled config (env var or a fixed deploy location), never
  # request input, so there is no traversal surface here.
  # sobelow_skip ["Traversal.FileModule"]
  defp load do
    case source() do
      nil ->
        %{}

      path ->
        path
        |> File.stream!()
        |> Enum.reduce(%{}, fn line, acc ->
          case line |> String.trim_trailing() |> String.split("\t") do
            [blz, bic, name] -> Map.put(acc, blz, {bic, name})
            _ -> acc
          end
        end)
    end
  end

  # First existing candidate path, or nil.
  defp source do
    [
      System.get_env("BLZ_DATA_FILE"),
      "/data/blz.tsv",
      Application.app_dir(:bbh, "priv/data/blz.tsv")
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.find(&File.regular?/1)
  end
end
