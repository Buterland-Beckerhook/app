defmodule Bbh.Altcha do
  @moduledoc """
  Self-hosted [Altcha](https://altcha.org) proof-of-work challenge/verification.
  No third party, no cookies. Enabled when `:bbh, :altcha_hmac_key` is configured;
  otherwise `enabled?/0` is false and the form skips verification (dev convenience).
  """
  alias Bbh.Altcha.ReplayCache

  @algorithm "SHA-256"
  @max_number 50_000
  # How long a challenge stays valid after it is issued.
  @ttl_seconds 300

  @doc "Whether Altcha verification is active (an HMAC key is configured)."
  def enabled?, do: not is_nil(hmac_key())

  @doc "Build a fresh challenge for the widget."
  def challenge do
    # The expiry is embedded in the salt; the salt is folded into the challenge
    # hash which is signed, so a client cannot tamper with it.
    expires = System.system_time(:second) + @ttl_seconds
    random = :crypto.strong_rand_bytes(12) |> Base.encode16(case: :lower)
    salt = random <> "." <> Integer.to_string(expires)
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
         {:ok, %{"algorithm" => @algorithm} = data} <- Jason.decode(json),
         %{"challenge" => challenge, "number" => number, "salt" => salt, "signature" => signature} <-
           data,
         expires when is_integer(expires) <- parse_expires(salt),
         true <- System.system_time(:second) <= expires,
         true <- valid_number?(number),
         true <- sha256(salt <> to_string(number)) == challenge,
         true <- Plug.Crypto.secure_compare(sign(challenge), signature),
         :ok <- ReplayCache.put_new(challenge, expires) do
      true
    else
      _ -> false
    end
  rescue
    _ -> false
  end

  # Bound the accepted solution by the same maxnumber advertised in the challenge.
  defp valid_number?(number) when is_integer(number), do: number >= 0 and number <= @max_number
  defp valid_number?(_), do: false

  defp parse_expires(salt) when is_binary(salt) do
    case salt |> String.split(".") |> List.last() |> Integer.parse() do
      {expires, ""} -> expires
      _ -> nil
    end
  end

  defp parse_expires(_), do: nil

  defp sha256(data), do: :crypto.hash(:sha256, data) |> Base.encode16(case: :lower)

  defp sign(challenge),
    do: :crypto.mac(:hmac, :sha256, hmac_key(), challenge) |> Base.encode16(case: :lower)

  defp hmac_key, do: Application.get_env(:bbh, :altcha_hmac_key)
end
