defmodule Bbh.Blz do
  @moduledoc """
  In-memory BLZ → {BIC, bank name} lookup, used to derive BIC/Kreditinstitut from a
  German IBAN on the membership form.

  The table is the stripped Bundesbank "Bankleitzahlendatei". It is loaded at boot
  into `:persistent_term` — a few thousand read-only entries, no per-lookup process
  hop, no GC churn — and reloaded when an admin imports a new file at
  `/admin/bankleitzahlen` (`import/1`) or removes that upload again (`reset/0`).

  Everything degrades gracefully: if no data file is found (or it is outdated and a
  BLZ is missing), lookups simply return `:error` and the caller leaves the fields
  blank. The file is resolved in this order, first hit wins:

    1. the uploaded table at `:upload_file` (`/data/blz.tsv` in the data volume,
       `BLZ_DATA_FILE` overrides) — written by `import/1`, refreshable without a
       rebuild.
    2. `priv/data/blz.tsv` — the copy shipped in the release (`mix bbh.blz.strip`).

  An upload keeps winning over a newer shipped copy until it is removed; the admin
  page says which one is active.
  """
  use GenServer

  require Logger

  @pt_key {__MODULE__, :map}

  # Where the Bundesbank publishes the quarterly file. The page is stable; the
  # download links on it change with every release, so we link the page.
  @download_page "https://www.bundesbank.de/de/aufgaben/unbarer-zahlungsverkehr/serviceangebot/bankleitzahlen/download-bankleitzahlen-602592"

  @type table :: %{String.t() => {String.t(), String.t()}}

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @doc "The Bundesbank page offering the current Bankleitzahlendatei."
  def download_page, do: @download_page

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

  @doc """
  Which table is active: `:upload` (with the time it was written), `:shipped`, or
  `:none`, plus the number of loaded entries.
  """
  def status do
    source =
      case source() do
        nil ->
          :none

        path ->
          if path == upload_file(), do: :upload, else: :shipped
      end

    uploaded_at =
      with :upload <- source,
           {:ok, %File.Stat{mtime: mtime}} <- File.stat(upload_file(), time: :posix) do
        DateTime.from_unix!(mtime)
      else
        _ -> nil
      end

    %{source: source, entries: size(), uploaded_at: uploaded_at}
  end

  @doc """
  Parse the Bundesbank "Bankleitzahlendatei" (CSV) into a table.

  The source is a `;`-separated, `"`-quoted file with one row per bank branch,
  published in ISO-8859-1 (a UTF-8 re-save is accepted too). We keep only the
  *leading* record per Bankleitzahl (`Merkmal == "1"`, the Hauptstelle) that carries
  a well-formed BIC. Returns `{:error, :too_few_entries}` when the result is too
  small to be the real file — a wrong upload must not replace a working table.
  """
  @spec parse_bundesbank(binary()) :: {:ok, table()} | {:error, :too_few_entries}
  def parse_bundesbank(content) when is_binary(content) do
    content = if String.valid?(content), do: content, else: latin1_to_utf8(content)

    table =
      content
      |> String.split(~r/\r?\n/, trim: true)
      |> Enum.drop(1)
      |> Enum.flat_map(&parse_line/1)
      |> Enum.reduce(%{}, fn {blz, bic, name}, acc -> Map.put_new(acc, blz, {bic, name}) end)

    if map_size(table) >= min_entries(), do: {:ok, table}, else: {:error, :too_few_entries}
  end

  defp latin1_to_utf8(content), do: :unicode.characters_to_binary(content, :latin1)

  defp parse_line(line) do
    fields = line |> String.split(";") |> Enum.map(&unquote_field/1)

    with [blz, "1" | _] <- fields,
         true <- blz =~ ~r/\A\d{8}\z/,
         bic = Enum.at(fields, 7, ""),
         true <- bic =~ ~r/\A[A-Z0-9]{8}([A-Z0-9]{3})?\z/ do
      [{blz, bic, fields |> Enum.at(2, "") |> String.replace(~r/\s+/, " ")}]
    else
      _ -> []
    end
  end

  defp unquote_field(field) do
    field |> String.trim() |> String.trim("\"") |> String.trim()
  end

  @doc "A table as the UTF-8 TSV (`BLZ<TAB>BIC<TAB>Bezeichnung`, sorted by BLZ) we store."
  @spec encode(table()) :: iodata()
  def encode(table) do
    table
    |> Enum.sort_by(fn {blz, _} -> blz end)
    |> Enum.map(fn {blz, {bic, name}} -> [blz, ?\t, bic, ?\t, name, ?\n] end)
  end

  @doc """
  What `table` changes against the loaded one: added and removed entries as
  `{blz, bic, name}`, changed ones as `{blz, {old_bic, old_name}, {new_bic, new_name}}`,
  each sorted by BLZ.
  """
  def diff(table) do
    current = table()

    added = for {blz, {bic, name}} <- table, not Map.has_key?(current, blz), do: {blz, bic, name}

    removed =
      for {blz, {bic, name}} <- current, not Map.has_key?(table, blz), do: {blz, bic, name}

    changed =
      for {blz, new} <- table, old = Map.get(current, blz), old && old != new, do: {blz, old, new}

    %{
      added: Enum.sort(added),
      removed: Enum.sort(removed),
      changed: Enum.sort(changed)
    }
  end

  @doc """
  Store `table` as the uploaded table and load it. The file is written next to its
  destination and renamed into place, so a crash never leaves half a table behind.
  """
  # The path is operator config (`:upload_file`), never request input.
  # sobelow_skip ["Traversal.FileModule"]
  def import(table) when is_map(table) do
    path = upload_file()
    tmp = path <> ".tmp"

    with :ok <- File.mkdir_p(Path.dirname(path)),
         :ok <- File.write(tmp, encode(table)),
         :ok <- File.rename(tmp, path) do
      reload()
    else
      {:error, reason} ->
        File.rm(tmp)
        {:error, reason}
    end
  end

  @doc "Remove the uploaded table, falling back to the shipped copy."
  # sobelow_skip ["Traversal.FileModule"]
  def reset do
    case File.rm(upload_file()) do
      result when result in [:ok, {:error, :enoent}] -> reload()
      error -> error
    end
  end

  @doc "Re-read the data file into `:persistent_term`."
  def reload, do: GenServer.call(__MODULE__, :reload)

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

  @impl true
  def handle_call(:reload, _from, state) do
    map = load()
    Logger.info("[blz] reloaded #{map_size(map)} BLZ entries from #{source() || "?"}")
    :persistent_term.put(@pt_key, map)
    {:reply, :ok, state}
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
    [upload_file(), Application.app_dir(:bbh, "priv/data/blz.tsv")]
    |> Enum.reject(&is_nil/1)
    |> Enum.find(&File.regular?/1)
  end

  defp upload_file, do: config(:upload_file)
  defp min_entries, do: config(:min_entries) || 1_000

  defp config(key), do: :bbh |> Application.get_env(__MODULE__, []) |> Keyword.get(key)
end
