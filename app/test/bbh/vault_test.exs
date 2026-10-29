defmodule Bbh.VaultTest do
  # Not async: some tests swap the application's key configuration.
  use ExUnit.Case, async: false

  alias Bbh.Vault

  @aad "tickets.subject_enc:7f1b"

  defp with_config(overrides) do
    previous = Application.get_env(:bbh, Vault)
    Application.put_env(:bbh, Vault, Keyword.merge(previous, overrides))
    on_exit(fn -> Application.put_env(:bbh, Vault, previous) end)
  end

  test "round-trips and uses a fresh IV each time" do
    a = Vault.encrypt("Anfrage zum Schützenfest", @aad)
    b = Vault.encrypt("Anfrage zum Schützenfest", @aad)

    assert a != b
    assert Vault.decrypt(a, @aad) == {:ok, "Anfrage zum Schützenfest"}
    refute a =~ "Schützenfest"
  end

  test "writes with the current key id" do
    assert <<1, 2, _::binary>> = Vault.encrypt("x", @aad)
  end

  test "nil stays nil" do
    assert Vault.encrypt(nil, @aad) == nil
    assert Vault.decrypt(nil, @aad) == {:ok, nil}
  end

  test "fails with other associated data — a value moved to another row or column" do
    value = Vault.encrypt("geheim", @aad)
    assert Vault.decrypt(value, "tickets.subject_enc:other") == :error
    assert Vault.decrypt(value, "tickets.payload_enc:7f1b") == :error
    assert_raise ArgumentError, fn -> Vault.decrypt!(value, "tickets.subject_enc:other") end
  end

  test "fails on tampering and garbage" do
    <<head::binary-size(30), last, rest::binary>> = Vault.encrypt("geheim", @aad)
    assert Vault.decrypt(<<head::binary, Bitwise.bxor(last, 1), rest::binary>>, @aad) == :error
    assert Vault.decrypt("plain text", @aad) == :error
    assert Vault.decrypt(<<1, 99, 0::size(28 * 8)>>, @aad) == :error
  end

  describe "rotation" do
    test "an old key still decrypts and rekey moves the value to the current key" do
      with_config(current_key: "1")
      old = Vault.encrypt("alt", @aad)
      assert <<1, 1, _::binary>> = old

      with_config(current_key: "2")
      assert Vault.decrypt(old, @aad) == {:ok, "alt"}
      assert {:ok, <<1, 2, _::binary>> = new} = Vault.rekey(old, @aad)
      assert Vault.decrypt(new, @aad) == {:ok, "alt"}
      assert Vault.rekey(new, @aad) == :unchanged
      assert Vault.rekey(nil, @aad) == :unchanged
    end

    test "a value whose key was dropped no longer decrypts" do
      with_config(current_key: "1")
      old = Vault.encrypt("alt", @aad)

      with_config(keys: "2:OY9GKth7niWJ7Ypg+qyWEqoFown+XJyH7s8F7HgXimk=", current_key: "2")
      assert Vault.decrypt(old, @aad) == :error
    end
  end

  describe "blind_index/1" do
    test "is stable across case and whitespace and reveals nothing" do
      index = Vault.blind_index(" Max@Example.com ")
      assert index == Vault.blind_index("max@example.com")
      assert byte_size(index) == 32
      assert index != Vault.blind_index("moritz@example.com")
    end
  end

  describe "configuration" do
    test "check! accepts the test configuration" do
      assert Vault.check!() == :ok
      assert Vault.configured?()
    end

    test "check! names what is wrong" do
      base = Application.get_env(:bbh, Vault)
      on_exit(fn -> Application.put_env(:bbh, Vault, base) end)

      for {overrides, message} <- [
            {[keys: nil], "TICKET_KEYS is not set"},
            {[keys: "1:dG9vIHNob3J0"], "TICKET_KEYS entry 1 must be base64 of 32 bytes"},
            {[keys: "eins"], "must look like 1:<base64 key>"},
            {[current_key: "3"], "TICKET_KEY_CURRENT must name one"},
            {[hmac_key: nil], "TICKET_HMAC_KEY is not set"}
          ] do
        Application.put_env(:bbh, Vault, Keyword.merge(base, overrides))
        error = assert_raise ArgumentError, fn -> Vault.check!() end
        assert error.message =~ message
        refute Vault.configured?()
      end
    end

    test "generate_key/0 produces a usable key" do
      key = Vault.generate_key()
      with_config(keys: "7:#{key}", current_key: "7")
      assert Vault.decrypt(Vault.encrypt("x", @aad), @aad) == {:ok, "x"}
    end
  end

  describe "changeset helpers" do
    defmodule Row do
      use Ecto.Schema

      @primary_key {:id, :binary_id, autogenerate: true}
      embedded_schema do
        field :subject, :string, virtual: true
        field :subject_enc, :binary
        field :payload, :map, virtual: true
        field :payload_enc, :binary
      end
    end

    @fields [{:subject, :subject_enc}, {:payload, :payload_enc, :map}]

    test "encrypt_changes assigns an id and binds the ciphertext to it" do
      changeset =
        %Row{}
        |> Ecto.Changeset.cast(%{subject: "Hallo", payload: %{"iban" => "DE89"}}, [
          :subject,
          :payload
        ])
        |> Vault.encrypt_changes("rows", @fields)

      id = Ecto.Changeset.get_change(changeset, :id)
      assert is_binary(id)

      row = Ecto.Changeset.apply_changes(changeset)
      assert Vault.decrypt(row.subject_enc, "rows.subject_enc:#{id}") == {:ok, "Hallo"}

      loaded =
        Vault.decrypt_fields(
          %Row{id: id, subject_enc: row.subject_enc, payload_enc: row.payload_enc},
          "rows",
          @fields
        )

      assert loaded.subject == "Hallo"
      assert loaded.payload == %{"iban" => "DE89"}
    end

    test "leaves untouched fields alone and keeps an existing id" do
      changeset =
        %Row{id: "fixed"}
        |> Ecto.Changeset.cast(%{subject: "Neu"}, [:subject])
        |> Vault.encrypt_changes("rows", @fields)

      refute Ecto.Changeset.get_change(changeset, :id)
      refute Ecto.Changeset.get_change(changeset, :payload_enc)
      assert Ecto.Changeset.get_change(changeset, :subject_enc)
    end
  end
end
