defmodule Bbh.AltchaTest do
  # async: false — mutates the global :bbh, :altcha_hmac_key application env.
  use ExUnit.Case, async: false

  alias Bbh.Altcha

  @key "test-altcha-hmac-key"

  defp sha256(data), do: :crypto.hash(:sha256, data) |> Base.encode16(case: :lower)

  # Solve the proof-of-work: find the number whose salted hash matches the challenge.
  defp solve(%{challenge: challenge, salt: salt}) do
    Enum.find(0..50_000, fn n -> sha256(salt <> Integer.to_string(n)) == challenge end)
  end

  defp payload(challenge, number) do
    %{
      "algorithm" => challenge.algorithm,
      "challenge" => challenge.challenge,
      "number" => number,
      "salt" => challenge.salt,
      "signature" => challenge.signature
    }
    |> Jason.encode!()
    |> Base.encode64()
  end

  describe "enabled?/0" do
    test "false when no key is configured" do
      Application.delete_env(:bbh, :altcha_hmac_key)
      refute Altcha.enabled?()
    end

    test "true when a key is configured" do
      Application.put_env(:bbh, :altcha_hmac_key, @key)
      on_exit(fn -> Application.delete_env(:bbh, :altcha_hmac_key) end)
      assert Altcha.enabled?()
    end
  end

  describe "verify/1" do
    setup do
      Application.put_env(:bbh, :altcha_hmac_key, @key)
      on_exit(fn -> Application.delete_env(:bbh, :altcha_hmac_key) end)
      :ok
    end

    test "accepts a correctly solved and signed challenge" do
      challenge = Altcha.challenge()
      number = solve(challenge)
      assert is_integer(number)

      assert Altcha.verify(payload(challenge, number))
    end

    test "rejects a tampered number" do
      challenge = Altcha.challenge()
      number = solve(challenge)

      refute Altcha.verify(payload(challenge, number + 1))
    end

    test "rejects nil, empty and garbage payloads" do
      refute Altcha.verify(nil)
      refute Altcha.verify("")
      refute Altcha.verify("not-base64-json")
    end
  end
end
