defmodule Bbh.Accounts.Passkeys do
  @moduledoc """
  WebAuthn passkey ceremonies (registration + authentication) and credential
  management, built on the `Wax` library.

  Both ceremonies are driven from a connected LiveView: the server generates a
  `%Wax.Challenge{}`, ships only `challenge.bytes` to the browser, and verifies
  the browser's response against the challenge held in the LiveView's assigns.

  `origin`/`rp_id` are derived from the endpoint at call time so dev
  (`localhost`), test and prod all work with no static configuration.
  """
  import Ecto.Query, warn: false

  alias Bbh.Accounts
  alias Bbh.Accounts.UserPasskey
  alias Bbh.Repo

  # The WebAuthn library, indirected so tests can stub the crypto edge.
  defp wax, do: Application.get_env(:bbh, :wax_module, Wax)

  defp rp_id, do: BbhWeb.Endpoint.host()
  defp origin, do: BbhWeb.Endpoint.url()

  ## Registration (attestation)

  @doc "Builds a registration challenge for the given user."
  def new_registration_challenge(_user) do
    Wax.new_registration_challenge(
      origin: origin(),
      rp_id: rp_id(),
      user_verification: "required"
    )
  end

  @doc """
  Verifies a registration response and stores the new credential.

  Returns `{:ok, %UserPasskey{}}` on success or `{:error, reason}` — including on
  malformed base64 input, so callers never crash on attacker-supplied params.

  `params` are the base64url-encoded fields posted back by the browser
  (`rawId`, `attestationObject`, `clientDataJSON`).
  """
  def complete_registration(user, %Wax.Challenge{} = challenge, params, nickname) do
    with {:ok, attestation_object} <- b64_decode(params["attestationObject"]),
         {:ok, client_data_json} <- b64_decode(params["clientDataJSON"]),
         {:ok, raw_id} <- b64_decode(params["rawId"]),
         {:ok, {auth_data, _attestation}} <-
           wax().register(attestation_object, client_data_json, challenge) do
      acd = auth_data.attested_credential_data

      %UserPasskey{}
      |> UserPasskey.changeset(%{
        user_id: user.id,
        credential_id: raw_id,
        public_key: acd.credential_public_key,
        aaguid: acd.aaguid,
        sign_count: auth_data.sign_count,
        nickname: nickname
      })
      |> Repo.insert()
    end
  end

  ## Authentication (assertion) — usernameless / discoverable

  @doc "Builds an authentication challenge (no allow_credentials — discoverable)."
  def new_authentication_challenge do
    Wax.new_authentication_challenge(
      origin: origin(),
      rp_id: rp_id(),
      user_verification: "required"
    )
  end

  @doc """
  Verifies an authentication assertion and returns the authenticated user.

  Looks the credential up by its (unique) id, verifies the assertion against the
  stored public key, guards against sign-count regression (authenticator
  cloning), and records the new counter + last-used timestamp.
  """
  def complete_authentication(%Wax.Challenge{} = challenge, params) do
    with {:ok, raw_id} <- b64_decode(params["rawId"]),
         {:ok, auth_data_bin} <- b64_decode(params["authenticatorData"]),
         {:ok, sig} <- b64_decode(params["signature"]),
         {:ok, client_data_json} <- b64_decode(params["clientDataJSON"]),
         %UserPasskey{} = passkey <- get_by_credential_id(raw_id),
         {:ok, auth_data} <-
           wax().authenticate(
             raw_id,
             auth_data_bin,
             sig,
             client_data_json,
             challenge,
             [{raw_id, passkey.public_key}]
           ),
         :ok <- check_sign_count(passkey, auth_data.sign_count) do
      touch_passkey!(passkey, auth_data.sign_count)
      {:ok, Accounts.get_user!(passkey.user_id)}
    else
      nil -> {:error, :unknown_credential}
      {:error, _} = error -> error
    end
  end

  ## Credential management

  @doc "Lists a user's passkeys, oldest first."
  def list_passkeys(user) do
    Repo.all(from p in UserPasskey, where: p.user_id == ^user.id, order_by: [asc: p.inserted_at])
  end

  @doc "Deletes one of the user's own passkeys."
  def delete_passkey(user, id) do
    case Repo.get_by(UserPasskey, id: id, user_id: user.id) do
      nil -> {:error, :not_found}
      passkey -> Repo.delete(passkey)
    end
  end

  @doc "Raw credential ids for a user, to populate `excludeCredentials` on registration."
  def credential_ids(user) do
    Repo.all(from p in UserPasskey, where: p.user_id == ^user.id, select: p.credential_id)
  end

  @doc "Whether the user has at least one passkey."
  def has_passkey?(user) do
    Repo.exists?(from p in UserPasskey, where: p.user_id == ^user.id)
  end

  @doc "MapSet of user ids that have at least one passkey (for list views)."
  def user_ids_with_passkeys do
    UserPasskey
    |> select([p], p.user_id)
    |> distinct(true)
    |> Repo.all()
    |> MapSet.new()
  end

  defp get_by_credential_id(credential_id) do
    Repo.get_by(UserPasskey, credential_id: credential_id)
  end

  # An authenticator that doesn't implement the signature counter always reports
  # 0, and its stored count is therefore also 0 — accept that. But a stored
  # count > 0 followed by an incoming 0 (or any non-increase) is exactly the
  # clone signal the counter exists to catch, so reject it.
  defp check_sign_count(%UserPasskey{sign_count: 0}, 0), do: :ok
  defp check_sign_count(%UserPasskey{sign_count: prev}, new) when new > prev, do: :ok
  defp check_sign_count(_passkey, _new), do: {:error, :sign_count_regression}

  defp touch_passkey!(passkey, new_count) do
    passkey
    |> Ecto.Changeset.change(sign_count: new_count, last_used_at: DateTime.utc_now(:second))
    |> Repo.update!()
  end

  defp b64_decode(nil), do: {:error, :missing_param}

  defp b64_decode(value) when is_binary(value) do
    case Base.url_decode64(value, padding: false) do
      {:ok, bytes} -> {:ok, bytes}
      # Base.url_decode64/2 returns a bare :error on malformed input; normalize
      # it so the `with` chains never hit a WithClauseError on attacker input.
      :error -> {:error, :invalid_base64}
    end
  end

  defp b64_decode(_), do: {:error, :invalid_param}
end
