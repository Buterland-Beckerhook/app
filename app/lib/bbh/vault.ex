defmodule Bbh.Vault do
  @moduledoc """
  Field encryption for personal data at rest (the Postfach, `docs/plans/ticket-system.md`
  §5.1): AES-256-GCM via `:crypto`, so a database dump or backup is unreadable without
  the key. Not a defence against a compromised running app — key and data share a host.

  ## Ciphertext

      <<format::8, key_id::8, iv::binary-12, tag::binary-16, ciphertext::binary>>

  A fresh random 96-bit IV per value. `key_id` names the key it was written with, so old
  keys stay readable after a rotation and `rekey/2` can move a value to the current one.

  ## Associated data

  Every value is bound to where it lives — `aad(table, column, row_id)`, e.g.
  `"tickets.subject_enc:<uuid>"`. A ciphertext copied into another row or column fails
  to decrypt. That needs the row id before the insert, which `encrypt_changes/3` sees to.

  ## Keys

  From the environment (`config/runtime.exs`), base64 of 32 random bytes each
  (`mix bbh.vault.gen_key`):

    * `TICKET_KEYS="1:<key>,2:<key>"` — every key still needed for reading
    * `TICKET_KEY_CURRENT=2` — the one new values are written with
    * `TICKET_HMAC_KEY=<key>` — for `blind_index/1`

  The keys are backed up outside the server backup (club password manager); a dump
  next to its key would make the encryption pointless.
  """

  @format 1
  @iv_size 12
  @tag_size 16
  @key_size 32

  @doc "Encrypts `plaintext` (nil stays nil) with the current key, bound to `aad`."
  def encrypt(nil, _aad), do: nil

  def encrypt(plaintext, aad) when is_binary(plaintext) and is_binary(aad) do
    %{keys: keys, current: key_id} = config!()
    iv = :crypto.strong_rand_bytes(@iv_size)

    {ciphertext, tag} =
      :crypto.crypto_one_time_aead(
        :aes_256_gcm,
        Map.fetch!(keys, key_id),
        iv,
        plaintext,
        aad,
        @tag_size,
        true
      )

    <<@format, key_id, iv::binary, tag::binary, ciphertext::binary>>
  end

  @doc "Decrypts a value written by `encrypt/2` with the same `aad`."
  def decrypt(nil, _aad), do: {:ok, nil}

  def decrypt(
        <<@format, key_id, iv::binary-size(@iv_size), tag::binary-size(@tag_size),
          ciphertext::binary>>,
        aad
      )
      when is_binary(aad) do
    with {:ok, key} <- Map.fetch(config!().keys, key_id),
         plaintext when is_binary(plaintext) <-
           :crypto.crypto_one_time_aead(:aes_256_gcm, key, iv, ciphertext, aad, tag, false) do
      {:ok, plaintext}
    else
      _ -> :error
    end
  end

  def decrypt(_value, _aad), do: :error

  @doc "Like `decrypt/2`, but raises — a value that fails to decrypt is a bug or tampering."
  def decrypt!(value, aad) do
    case decrypt(value, aad) do
      {:ok, plaintext} -> plaintext
      :error -> raise ArgumentError, "cannot decrypt value for #{aad}"
    end
  end

  @doc """
  Re-encrypts a value with the current key. `:unchanged` when it already uses it (or is
  nil), `:error` when it does not decrypt.
  """
  def rekey(nil, _aad), do: :unchanged

  def rekey(<<@format, key_id, _::binary>> = value, aad) do
    if key_id == config!().current do
      :unchanged
    else
      with {:ok, plaintext} <- decrypt(value, aad), do: {:ok, encrypt(plaintext, aad)}
    end
  end

  def rekey(_value, _aad), do: :error

  @doc "The associated data binding a value to its table, column and row."
  def aad(table, column, id), do: "#{table}.#{column}:#{id}"

  @doc """
  Blind index of an e-mail address: HMAC-SHA256 over the trimmed, lower-cased address.
  Finds all rows of one sender without storing the address in the clear.
  """
  def blind_index(nil), do: nil

  def blind_index(value) when is_binary(value) do
    normalized = value |> String.trim() |> String.downcase()
    :crypto.mac(:hmac, :sha256, config!().hmac_key, normalized)
  end

  ## Changeset and struct helpers

  @doc """
  Encrypts the changed virtual fields of a changeset into their columns.

  `fields` lists `{virtual, column}` or `{virtual, column, :map}` (a map, stored as
  JSON). A new record gets its id here, so the associated data can name it.
  """
  def encrypt_changes(%Ecto.Changeset{} = changeset, table, fields) do
    changeset = ensure_id(changeset)
    id = Ecto.Changeset.get_field(changeset, :id)

    Enum.reduce(fields, changeset, fn spec, cs ->
      {virtual, column, kind} = normalize_spec(spec)

      case Ecto.Changeset.fetch_change(cs, virtual) do
        {:ok, value} ->
          Ecto.Changeset.put_change(
            cs,
            column,
            encrypt(dump(value, kind), aad(table, column, id))
          )

        :error ->
          cs
      end
    end)
  end

  @doc "Fills the virtual fields of a loaded struct from their encrypted columns."
  def decrypt_fields(nil, _table, _fields), do: nil

  def decrypt_fields(struct, table, fields) do
    Enum.reduce(fields, struct, fn spec, acc ->
      {virtual, column, kind} = normalize_spec(spec)
      plaintext = decrypt!(Map.fetch!(acc, column), aad(table, column, acc.id))
      Map.put(acc, virtual, load(plaintext, kind))
    end)
  end

  defp ensure_id(changeset) do
    if Ecto.Changeset.get_field(changeset, :id),
      do: changeset,
      else: Ecto.Changeset.put_change(changeset, :id, Ecto.UUID.generate())
  end

  defp normalize_spec({virtual, column}), do: {virtual, column, :string}
  defp normalize_spec({_, _, _} = spec), do: spec

  defp dump(nil, _kind), do: nil
  defp dump(value, :map), do: Jason.encode!(value)
  defp dump(value, :string), do: value

  defp load(nil, _kind), do: nil
  defp load(json, :map), do: Jason.decode!(json)
  defp load(value, :string), do: value

  ## Keys

  @doc "A new key, base64 of 32 random bytes."
  def generate_key, do: @key_size |> :crypto.strong_rand_bytes() |> Base.encode64()

  @doc "Whether keys are configured at all."
  def configured?, do: match?({:ok, _}, load_config())

  @doc """
  Validates the key configuration and raises with a readable message when it is
  missing or broken. Called at boot when the Postfach is enabled — refusing to start
  beats storing personal data in the clear.
  """
  def check! do
    case load_config() do
      {:ok, _} -> :ok
      {:error, reason} -> raise ArgumentError, "Bbh.Vault: #{reason}"
    end
  end

  defp config! do
    case load_config() do
      {:ok, config} -> config
      {:error, reason} -> raise ArgumentError, "Bbh.Vault: #{reason}"
    end
  end

  # Parsed once per configuration; the raw env strings are the cache key, so a test or a
  # runtime config change is picked up.
  defp load_config do
    raw = Application.get_env(:bbh, __MODULE__, [])
    cache_key = {__MODULE__, :config}

    case :persistent_term.get(cache_key, nil) do
      {^raw, result} ->
        result

      _ ->
        result = parse(raw)
        :persistent_term.put(cache_key, {raw, result})
        result
    end
  end

  defp parse(raw) do
    with {:ok, keys} <- parse_keys(raw[:keys]),
         {:ok, current} <- parse_current(raw[:current_key], keys),
         {:ok, hmac_key} <- decode_key(raw[:hmac_key], "TICKET_HMAC_KEY") do
      {:ok, %{keys: keys, current: current, hmac_key: hmac_key}}
    end
  end

  defp parse_keys(value) when value in [nil, ""], do: {:error, "TICKET_KEYS is not set"}

  defp parse_keys(value) do
    value
    |> String.split(",", trim: true)
    |> Enum.reduce_while({:ok, %{}}, fn entry, {:ok, acc} ->
      with [id, encoded] <- String.split(String.trim(entry), ":", parts: 2),
           {id, ""} when id in 1..255 <- Integer.parse(id),
           {:ok, key} <- decode_key(encoded, "TICKET_KEYS entry #{id}") do
        {:cont, {:ok, Map.put(acc, id, key)}}
      else
        {:error, _} = error -> {:halt, error}
        _ -> {:halt, {:error, "TICKET_KEYS entries must look like 1:<base64 key>"}}
      end
    end)
  end

  defp parse_current(value, keys) do
    with value when is_binary(value) <- value,
         {id, ""} <- Integer.parse(value),
         true <- Map.has_key?(keys, id) do
      {:ok, id}
    else
      _ -> {:error, "TICKET_KEY_CURRENT must name one of the TICKET_KEYS ids"}
    end
  end

  defp decode_key(value, name) when is_binary(value) do
    case Base.decode64(String.trim(value)) do
      {:ok, <<_::binary-size(@key_size)>> = key} -> {:ok, key}
      _ -> {:error, "#{name} must be base64 of #{@key_size} bytes"}
    end
  end

  defp decode_key(_value, name), do: {:error, "#{name} is not set"}
end
