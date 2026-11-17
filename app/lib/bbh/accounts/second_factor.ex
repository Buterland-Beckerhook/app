defmodule Bbh.Accounts.SecondFactor do
  @moduledoc """
  The TOTP second factor (enrolment, codes, replay protection) and the admin's reset of
  all second factors. Passkeys have their own module (`Bbh.Accounts.Passkeys`).
  """
  import Ecto.Query, warn: false

  alias Bbh.Accounts.{User, UserPasskey, UserToken}
  alias Bbh.Repo

  ## TOTP two-factor authentication

  @doc "Generate a fresh TOTP secret (not yet persisted)."
  def generate_totp_secret, do: NimbleTOTP.secret()

  @doc "otpauth:// URI for authenticator apps (QR code)."
  def totp_uri(%User{email: email}, secret) do
    NimbleTOTP.otpauth_uri("Buterland-Beckerhook:#{email}", secret,
      issuer: "Buterland-Beckerhook"
    )
  end

  # How far back a code may come from: one 30 s period, as RFC 6238 §5.2 suggests, so a
  # code read off the phone at :29 and submitted at :31 still counts.
  @totp_drift_seconds 30
  # NimbleTOTP's default period, which the authenticator apps use too.
  @totp_period 30

  @doc """
  Validate a TOTP code against a raw secret: the current period's code, or the
  previous period's (`@totp_drift_seconds`).
  """
  def valid_totp?(secret, code, now \\ System.os_time(:second))

  def valid_totp?(secret, code, now) when is_binary(secret) and is_binary(code) do
    code = String.trim(code)

    code != "" and
      (NimbleTOTP.valid?(secret, code, time: now) or
         NimbleTOTP.valid?(secret, code, time: now - @totp_drift_seconds))
  end

  def valid_totp?(_secret, _code, _now), do: false

  @doc """
  Spend a code from the user's authenticator: `:ok` once per code, `:error` when it is
  wrong or was already accepted. Whoever watched or phished a code can therefore not
  reuse it in their own login while it is still valid.

  The accepted period is recorded with a conditional update, so of two concurrent
  requests with the same code only one gets `:ok`.
  """
  def use_user_totp(user, code, now \\ System.os_time(:second))

  def use_user_totp(%User{id: id, totp_secret: secret}, code, now)
      when is_binary(secret) and is_binary(code) do
    code = String.trim(code)

    step =
      code != "" &&
        Enum.find_value([now, now - @totp_drift_seconds], fn time ->
          NimbleTOTP.valid?(secret, code, time: time) && div(time, @totp_period)
        end)

    with step when is_integer(step) <- step,
         {1, _} <-
           Repo.update_all(
             from(u in User,
               where: u.id == ^id and (is_nil(u.totp_last_step) or u.totp_last_step < ^step)
             ),
             set: [totp_last_step: step]
           ) do
      :ok
    else
      _ -> :error
    end
  end

  def use_user_totp(_user, _code, _now), do: :error

  @doc "Enable TOTP for a user with a verified secret. Ends a pending factor reset."
  def enable_totp(%User{} = user, secret) do
    with {:ok, user} <-
           user
           |> Ecto.Changeset.change(
             totp_secret: secret,
             totp_confirmed_at: DateTime.utc_now(:second)
           )
           |> Repo.update() do
      clear_factor_reset(user)
      {:ok, user}
    end
  end

  @doc "Disable TOTP for a user."
  def disable_totp(%User{} = user) do
    user
    |> Ecto.Changeset.change(totp_secret: nil, totp_confirmed_at: nil)
    |> Repo.update()
  end

  ## Second-factor reset (admin)

  @doc """
  Resets the user's second factors so they can enroll new ones: removes all passkeys
  and TOTP, ends every session, and issues a one-time code
  (`UserToken.build_factor_reset_code/1`). Until the user has set up a new factor,
  enrolling one needs that code, so mailbox access alone is not enough.

  Returns `{:ok, {code, session_tokens}}`; the caller drops the live sockets of the
  returned session tokens (`BbhWeb.UserAuth.disconnect_sessions/1`).
  """
  def reset_second_factors(%User{} = user) do
    {code, reset_token} = UserToken.build_factor_reset_code(user)

    Repo.transact(fn ->
      sessions = Bbh.Accounts.list_user_session_tokens(user)
      Repo.delete_all(from p in UserPasskey, where: p.user_id == ^user.id)
      {:ok, _} = disable_totp(user)

      Repo.delete_all(
        from t in UserToken,
          where: t.user_id == ^user.id and t.context in ["session", "factor_reset"]
      )

      Repo.insert!(reset_token)
      {:ok, {code, sessions}}
    end)
  end

  @doc "Whether an admin reset is waiting for the user to re-enroll with its code."
  def factor_reset_pending?(%User{} = user),
    do: Repo.exists?(UserToken.factor_reset_query(user))

  @doc "Whether `code` is the user's current, unexpired factor-reset code."
  def valid_factor_reset_code?(%User{} = user, code) when is_binary(code),
    do: Repo.exists?(UserToken.verify_factor_reset_code_query(user, code))

  def valid_factor_reset_code?(_user, _code), do: false

  @doc "Ends a pending factor reset — once the user has enrolled a new factor."
  def clear_factor_reset(%User{} = user) do
    Repo.delete_all(UserToken.factor_reset_query(user))
    :ok
  end
end
