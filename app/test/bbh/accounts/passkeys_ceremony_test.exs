defmodule Bbh.Accounts.PasskeysCeremonyTest do
  @moduledoc """
  End-to-end passkey ceremony against the REAL `Wax` library (no stub), using a
  software authenticator that produces genuine attestations and assertions. This
  proves the crypto path, the origin/rp_id/challenge wiring, and the COSE-key
  storage round-trip actually work — the parts the stubbed tests can't cover.
  """
  # async: false — never overlap the Wax-stubbing module (see PasskeysTest).
  use Bbh.DataCase, async: false

  alias Bbh.Accounts.Passkeys
  alias Bbh.WebAuthnSoftwareAuthenticator, as: Authenticator

  import Bbh.AccountsFixtures

  setup do
    %{user: user_fixture()}
  end

  test "a real registration ceremony stores a usable credential", %{user: user} do
    challenge = Passkeys.new_registration_challenge(user)
    {params, _keys} = Authenticator.register(challenge)

    assert {:ok, passkey} = Passkeys.complete_registration(user, challenge, params, "My Key")
    assert passkey.nickname == "My Key"
    assert passkey.credential_id == Base.url_decode64!(params["rawId"], padding: false)
    # COSE key survives the Ecto.Type round-trip as an EC2 P-256 key.
    assert passkey.public_key[1] == 2
    assert passkey.public_key[3] == -7
    assert is_binary(passkey.public_key[-2])
  end

  test "a real authentication ceremony logs the registered user in", %{user: user} do
    reg_challenge = Passkeys.new_registration_challenge(user)
    {reg_params, keys} = Authenticator.register(reg_challenge)
    {:ok, _passkey} = Passkeys.complete_registration(user, reg_challenge, reg_params, "My Key")

    auth_challenge = Passkeys.new_authentication_challenge()

    auth_params =
      Authenticator.authenticate(auth_challenge, keys.credential_id, keys.private_key, 1)

    assert {:ok, authed} = Passkeys.complete_authentication(auth_challenge, auth_params)
    assert authed.id == user.id
  end

  test "a tampered signature is rejected by real verification", %{user: user} do
    reg_challenge = Passkeys.new_registration_challenge(user)
    {reg_params, keys} = Authenticator.register(reg_challenge)
    {:ok, _} = Passkeys.complete_registration(user, reg_challenge, reg_params, "My Key")

    auth_challenge = Passkeys.new_authentication_challenge()

    auth_params =
      Authenticator.authenticate(auth_challenge, keys.credential_id, keys.private_key, 1)

    tampered = %{auth_params | "signature" => Base.url_encode64("garbage", padding: false)}

    assert {:error, _} = Passkeys.complete_authentication(auth_challenge, tampered)
  end

  test "an assertion for the wrong challenge is rejected", %{user: user} do
    reg_challenge = Passkeys.new_registration_challenge(user)
    {reg_params, keys} = Authenticator.register(reg_challenge)
    {:ok, _} = Passkeys.complete_registration(user, reg_challenge, reg_params, "My Key")

    # Sign against one challenge but verify against a freshly issued one.
    signed_challenge = Passkeys.new_authentication_challenge()
    other_challenge = Passkeys.new_authentication_challenge()

    auth_params =
      Authenticator.authenticate(signed_challenge, keys.credential_id, keys.private_key, 1)

    assert {:error, _} = Passkeys.complete_authentication(other_challenge, auth_params)
  end
end
