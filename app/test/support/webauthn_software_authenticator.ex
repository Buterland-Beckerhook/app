defmodule Bbh.WebAuthnSoftwareAuthenticator do
  @moduledoc """
  A minimal software WebAuthn authenticator for tests.

  It produces genuine attestation objects and assertions — real EC P-256 keys,
  real ECDSA signatures, real CBOR — that pass verification by the actual `Wax`
  library. This lets us exercise `Bbh.Accounts.Passkeys` end-to-end through the
  real crypto path (no stub), mirroring exactly what a browser authenticator and
  our JS hook produce over the wire (pad-less base64url fields).
  """
  import Bitwise

  # Flags (WebAuthn authenticator data): UP = user present, UV = user verified,
  # AT = attested credential data included.
  @flag_up 0x01
  @flag_uv 0x04
  @flag_at 0x40

  @doc """
  Performs a registration ceremony against `challenge`.

  Returns `{params, %{credential_id: ..., private_key: ..., cose_key: ...}}`
  where `params` are the base64url fields our context/JS expect.
  """
  def register(%Wax.Challenge{} = challenge) do
    {public_key, private_key} = :crypto.generate_key(:ecdh, :secp256r1)
    <<4, x::binary-size(32), y::binary-size(32)>> = public_key
    credential_id = :crypto.strong_rand_bytes(16)

    cose_key = %{1 => 2, 3 => -7, -1 => 1, -2 => x, -3 => y}

    cose_cbor =
      CBOR.encode(%{
        1 => 2,
        3 => -7,
        -1 => 1,
        -2 => %CBOR.Tag{tag: :bytes, value: x},
        -3 => %CBOR.Tag{tag: :bytes, value: y}
      })

    attested_credential_data =
      <<0::128>> <>
        <<byte_size(credential_id)::unsigned-big-integer-size(16)>> <>
        credential_id <> cose_cbor

    auth_data =
      rp_id_hash(challenge) <>
        <<@flag_up ||| @flag_uv ||| @flag_at>> <>
        <<0::unsigned-big-integer-size(32)>> <>
        attested_credential_data

    attestation_object =
      CBOR.encode(%{
        "fmt" => "none",
        "attStmt" => %{},
        "authData" => %CBOR.Tag{tag: :bytes, value: auth_data}
      })

    params = %{
      "rawId" => b64(credential_id),
      "attestationObject" => b64(attestation_object),
      "clientDataJSON" => b64(client_data_json(challenge, "webauthn.create"))
    }

    {params, %{credential_id: credential_id, private_key: private_key, cose_key: cose_key}}
  end

  @doc """
  Performs an authentication ceremony for `credential_id` signed with
  `private_key`. `sign_count` controls the returned signature counter.
  """
  def authenticate(%Wax.Challenge{} = challenge, credential_id, private_key, sign_count) do
    client_data = client_data_json(challenge, "webauthn.get")

    auth_data =
      rp_id_hash(challenge) <>
        <<@flag_up ||| @flag_uv>> <> <<sign_count::unsigned-big-integer-size(32)>>

    signature =
      :crypto.sign(
        :ecdsa,
        :sha256,
        auth_data <> :crypto.hash(:sha256, client_data),
        [private_key, :secp256r1]
      )

    %{
      "rawId" => b64(credential_id),
      "authenticatorData" => b64(auth_data),
      "signature" => b64(signature),
      "clientDataJSON" => b64(client_data)
    }
  end

  defp rp_id_hash(challenge), do: :crypto.hash(:sha256, challenge.rp_id)

  defp client_data_json(challenge, type) do
    Jason.encode!(%{
      type: type,
      challenge: Base.url_encode64(challenge.bytes, padding: false),
      origin: challenge.origin
    })
  end

  defp b64(bytes), do: Base.url_encode64(bytes, padding: false)
end
