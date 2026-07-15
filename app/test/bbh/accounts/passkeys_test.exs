defmodule Bbh.Accounts.PasskeysTest do
  # async: false — installs a global Wax stub via Application env.
  use Bbh.DataCase, async: false

  alias Bbh.Accounts.Passkeys
  alias Bbh.Accounts.UserPasskey
  alias Bbh.Repo

  import Bbh.AccountsFixtures

  setup do
    Bbh.WaxStub.install(&on_exit/1)
    %{user: user_fixture()}
  end

  describe "list_passkeys/1" do
    test "returns only the user's own passkeys, oldest first", %{user: user} do
      other = user_fixture()
      a = passkey_fixture(user, nickname: "A")
      b = passkey_fixture(user, nickname: "B")
      _foreign = passkey_fixture(other, nickname: "Foreign")

      assert [%UserPasskey{id: id_a}, %UserPasskey{id: id_b}] = Passkeys.list_passkeys(user)
      assert id_a == a.id
      assert id_b == b.id
    end
  end

  describe "credential_ids/1" do
    test "returns the raw credential ids for the user", %{user: user} do
      p = passkey_fixture(user)
      assert Passkeys.credential_ids(user) == [p.credential_id]
    end
  end

  describe "has_passkey?/1 and user_ids_with_passkeys/0" do
    test "reflect whether a user has any passkey", %{user: user} do
      other = user_fixture()
      refute Passkeys.has_passkey?(user)
      assert Passkeys.user_ids_with_passkeys() == MapSet.new()

      passkey_fixture(user)
      passkey_fixture(user, nickname: "second")

      assert Passkeys.has_passkey?(user)
      refute Passkeys.has_passkey?(other)
      # de-duplicated per user
      assert Passkeys.user_ids_with_passkeys() == MapSet.new([user.id])
    end
  end

  describe "delete_passkey/2" do
    test "deletes the user's own passkey", %{user: user} do
      p = passkey_fixture(user)
      assert {:ok, _} = Passkeys.delete_passkey(user, p.id)
      assert Passkeys.list_passkeys(user) == []
    end

    test "cannot delete another user's passkey", %{user: user} do
      other = user_fixture()
      p = passkey_fixture(other)

      assert {:error, :not_found} = Passkeys.delete_passkey(user, p.id)
      assert [%UserPasskey{}] = Passkeys.list_passkeys(other)
    end
  end

  describe "complete_registration/4" do
    test "stores the credential returned by the ceremony", %{user: user} do
      raw_id = :crypto.strong_rand_bytes(16)
      cose_key = %{1 => 2, 3 => -7, -1 => 1, -2 => <<1::256>>, -3 => <<2::256>>}

      Bbh.WaxStub.put_registration(
        {:ok,
         {%{
            attested_credential_data: %{credential_public_key: cose_key, aaguid: <<0::128>>},
            sign_count: 0
          }, {:none, nil, nil}}}
      )

      challenge = Passkeys.new_registration_challenge(user)

      params = %{
        "rawId" => Base.url_encode64(raw_id, padding: false),
        "attestationObject" => Base.url_encode64("att", padding: false),
        "clientDataJSON" => Base.url_encode64("cdj", padding: false)
      }

      assert {:ok, passkey} = Passkeys.complete_registration(user, challenge, params, "My Key")
      assert passkey.credential_id == raw_id
      assert passkey.public_key == cose_key
      assert passkey.nickname == "My Key"
      assert [%UserPasskey{}] = Passkeys.list_passkeys(user)
    end

    test "returns the error when the ceremony fails", %{user: user} do
      Bbh.WaxStub.put_registration({:error, %RuntimeError{message: "bad attestation"}})
      challenge = Passkeys.new_registration_challenge(user)

      params = %{
        "rawId" => Base.url_encode64("x", padding: false),
        "attestationObject" => Base.url_encode64("att", padding: false),
        "clientDataJSON" => Base.url_encode64("cdj", padding: false)
      }

      assert {:error, _} = Passkeys.complete_registration(user, challenge, params, "My Key")
      assert Passkeys.list_passkeys(user) == []
    end

    test "returns an error (no crash) on malformed base64 input", %{user: user} do
      challenge = Passkeys.new_registration_challenge(user)

      params = %{
        "rawId" => "!!!not base64!!!",
        "attestationObject" => Base.url_encode64("att", padding: false),
        "clientDataJSON" => Base.url_encode64("cdj", padding: false)
      }

      assert {:error, _} = Passkeys.complete_registration(user, challenge, params, "My Key")
      assert Passkeys.list_passkeys(user) == []
    end
  end

  describe "complete_authentication/2" do
    setup %{user: user} do
      raw_id = :crypto.strong_rand_bytes(16)
      passkey = passkey_fixture(user, credential_id: raw_id, sign_count: 5)
      challenge = Passkeys.new_authentication_challenge()

      params = %{
        "rawId" => Base.url_encode64(raw_id, padding: false),
        "authenticatorData" => Base.url_encode64("ad", padding: false),
        "signature" => Base.url_encode64("sig", padding: false),
        "clientDataJSON" => Base.url_encode64("cdj", padding: false)
      }

      %{passkey: passkey, challenge: challenge, params: params}
    end

    test "returns the user and bumps the sign counter", ctx do
      Bbh.WaxStub.put_authentication({:ok, %{sign_count: 6}})

      assert {:ok, user} = Passkeys.complete_authentication(ctx.challenge, ctx.params)
      assert user.id == ctx.user.id

      updated = Repo.get!(UserPasskey, ctx.passkey.id)
      assert updated.sign_count == 6
      assert updated.last_used_at
    end

    test "accepts a zero counter only when the stored counter is also zero", %{user: user} do
      raw_id = :crypto.strong_rand_bytes(16)
      passkey_fixture(user, credential_id: raw_id, sign_count: 0)
      challenge = Passkeys.new_authentication_challenge()

      params = %{
        "rawId" => Base.url_encode64(raw_id, padding: false),
        "authenticatorData" => Base.url_encode64("ad", padding: false),
        "signature" => Base.url_encode64("sig", padding: false),
        "clientDataJSON" => Base.url_encode64("cdj", padding: false)
      }

      Bbh.WaxStub.put_authentication({:ok, %{sign_count: 0}})
      assert {:ok, _user} = Passkeys.complete_authentication(challenge, params)
    end

    test "rejects a zero counter when the stored counter is non-zero (clone signal)", ctx do
      # Stored counter is 5 (from setup); a cloned authenticator reporting 0.
      Bbh.WaxStub.put_authentication({:ok, %{sign_count: 0}})

      assert {:error, :sign_count_regression} =
               Passkeys.complete_authentication(ctx.challenge, ctx.params)
    end

    test "rejects a non-increasing counter (clone detection)", ctx do
      Bbh.WaxStub.put_authentication({:ok, %{sign_count: 5}})

      assert {:error, :sign_count_regression} =
               Passkeys.complete_authentication(ctx.challenge, ctx.params)
    end

    test "returns an error (no crash) on malformed base64 input", ctx do
      params = %{ctx.params | "signature" => "!!!not base64!!!"}
      assert {:error, _} = Passkeys.complete_authentication(ctx.challenge, params)
    end

    test "returns :unknown_credential for an unregistered credential", ctx do
      params = %{ctx.params | "rawId" => Base.url_encode64("nope", padding: false)}

      assert {:error, :unknown_credential} =
               Passkeys.complete_authentication(ctx.challenge, params)
    end

    test "propagates a failed assertion", ctx do
      Bbh.WaxStub.put_authentication({:error, %RuntimeError{message: "bad signature"}})
      assert {:error, _} = Passkeys.complete_authentication(ctx.challenge, ctx.params)
    end
  end
end
