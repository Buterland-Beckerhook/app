defmodule Bbh.Altcha do
  @moduledoc """
  Self-hosted [Altcha](https://altcha.org) proof-of-work challenge/verification.
  No third party, no cookies. Enabled when `:bbh, :altcha_hmac_key` is configured;
  otherwise `enabled?/0` is false and the form skips verification (dev convenience).
  """
  @algorithm "SHA-256"
  @max_number 50_000

  @doc "Whether Altcha verification is active (an HMAC key is configured)."
  def enabled?, do: not is_nil(hmac_key())

  @doc "Build a fresh challenge for the widget."
  def challenge do
    salt = :crypto.strong_rand_bytes(12) |> Base.encode16(case: :lower)
    number = :rand.uniform(@max_number)
    challenge = sha256(salt <> Integer.to_string(number))

    %{
      algorithm: @algorithm,
      challenge: challenge,
      salt: salt,
      signature: sign(challenge),
      maxnumber: @max_number
    }
  end

  @doc "Verify a base64 Altcha payload submitted by the widget."
  def verify(nil), do: false
  def verify(""), do: false

  def verify(payload) when is_binary(payload) do
    with {:ok, json} <- Base.decode64(payload),
         {:ok, %{"algorithm" => @algorithm} = data} <- Jason.decode(json) do
      %{"challenge" => challenge, "number" => number, "salt" => salt, "signature" => signature} =
        data

      valid_challenge? = sha256(salt <> to_string(number)) == challenge
      valid_signature? = Plug.Crypto.secure_compare(sign(challenge), signature)

      valid_challenge? and valid_signature?
    else
      _ -> false
    end
  rescue
    _ -> false
  end

  defp sha256(data), do: :crypto.hash(:sha256, data) |> Base.encode16(case: :lower)

  defp sign(challenge),
    do: :crypto.mac(:hmac, :sha256, hmac_key(), challenge) |> Base.encode16(case: :lower)

  defp hmac_key, do: Application.get_env(:bbh, :altcha_hmac_key)
end
