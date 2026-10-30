defmodule Bbh.Accounts do
  @moduledoc """
  The Accounts context.
  """

  import Ecto.Query, warn: false
  alias Bbh.Repo

  alias Bbh.Accounts.{User, UserPasskey, UserToken, UserNotifier}

  ## Database getters

  @doc """
  Gets a user by email.

  ## Examples

      iex> get_user_by_email("foo@example.com")
      %User{}

      iex> get_user_by_email("unknown@example.com")
      nil

  """
  def get_user_by_email(email) when is_binary(email) do
    Repo.get_by(User, email: email)
  end

  @doc """
  Gets a single user.

  Raises `Ecto.NoResultsError` if the User does not exist.

  ## Examples

      iex> get_user!(123)
      %User{}

      iex> get_user!(456)
      ** (Ecto.NoResultsError)

  """
  def get_user!(id), do: Repo.get!(User, id)

  ## TOTP two-factor authentication

  @doc "Generate a fresh TOTP secret (not yet persisted)."
  def generate_totp_secret, do: NimbleTOTP.secret()

  @doc "otpauth:// URI for authenticator apps (QR code)."
  def totp_uri(%User{email: email}, secret) do
    NimbleTOTP.otpauth_uri("Buterland-Beckerhook:#{email}", secret,
      issuer: "Buterland-Beckerhook"
    )
  end

  @doc "Validate a TOTP code against a raw secret."
  def valid_totp?(secret, code) when is_binary(secret) and is_binary(code) do
    code = String.trim(code)
    code != "" and NimbleTOTP.valid?(secret, code)
  end

  def valid_totp?(_, _), do: false

  @doc "Validate a code against the user's stored TOTP secret."
  def valid_user_totp?(%User{totp_secret: secret}, code), do: valid_totp?(secret, code)

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
      sessions = list_user_session_tokens(user)
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

  ## User registration

  @doc """
  Registers a user.

  ## Examples

      iex> register_user(%{field: value})
      {:ok, %User{}}

      iex> register_user(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def register_user(attrs) do
    %User{}
    |> User.email_changeset(attrs)
    |> Repo.insert()
  end

  ## Admin user management

  def list_users, do: Repo.all(from u in User, order_by: u.email)

  @doc "How many users currently hold the admin role."
  def count_admins, do: Repo.aggregate(from(u in User, where: u.role == "admin"), :count)

  def delete_user(%User{} = user), do: Repo.delete(user)

  def update_user_role(%User{} = user, role),
    do: user |> User.role_changeset(%{role: role}) |> Repo.update()

  def update_user_calendars(%User{} = user, calendars),
    do: user |> User.calendars_changeset(%{calendars: calendars}) |> Repo.update()

  @doc "Invite a new user: create the account with a role and email an invitation link."
  def invite_user(attrs, magic_link_url_fun) do
    with {:ok, user} <- register_user(attrs),
         {:ok, user} <- update_user_role(user, attrs["role"] || "editor") do
      deliver_invite_instructions(user, magic_link_url_fun)
      {:ok, user}
    end
  end

  ## Settings

  @doc """
  Checks whether the user is in sudo mode.

  The user is in sudo mode when the last authentication was done no further
  than 20 minutes ago. The limit can be given as second argument in minutes.
  """
  def sudo_mode?(user, minutes \\ -20)

  def sudo_mode?(%User{authenticated_at: ts}, minutes) when is_struct(ts, DateTime) do
    DateTime.after?(ts, DateTime.utc_now() |> DateTime.add(minutes, :minute))
  end

  def sudo_mode?(_user, _minutes), do: false

  @doc """
  Returns an `%Ecto.Changeset{}` for changing the user email.

  See `Bbh.Accounts.User.email_changeset/3` for a list of supported options.

  ## Examples

      iex> change_user_email(user)
      %Ecto.Changeset{data: %User{}}

  """
  def change_user_email(user, attrs \\ %{}, opts \\ []) do
    User.email_changeset(user, attrs, opts)
  end

  @doc """
  Updates the user email using the given token.

  If the token matches, the user email is updated and the token is deleted.
  """
  def update_user_email(user, token) do
    context = "change:#{user.email}"

    Repo.transact(fn ->
      with {:ok, query} <- UserToken.verify_change_email_token_query(token, context),
           %UserToken{sent_to: email} <- Repo.one(query),
           {:ok, user} <- Repo.update(User.email_changeset(user, %{email: email})),
           {_count, _result} <-
             Repo.delete_all(from(UserToken, where: [user_id: ^user.id, context: ^context])) do
        {:ok, user}
      else
        _ -> {:error, :transaction_aborted}
      end
    end)
  end

  ## Session

  @doc """
  Generates a session token.
  """
  def generate_user_session_token(user) do
    {token, user_token} = UserToken.build_session_token(user)
    Repo.insert!(user_token)
    token
  end

  @doc """
  Gets the user with the given signed token.

  If the token is valid `{user, token_inserted_at}` is returned, otherwise `nil` is returned.
  """
  def get_user_by_session_token(token) do
    {:ok, query} = UserToken.verify_session_token_query(token)
    Repo.one(query)
  end

  @doc """
  Gets the user with the given magic link token.
  """
  def get_user_by_magic_link_token(token) do
    with {:ok, query} <- UserToken.verify_magic_link_token_query(token),
         {user, _token} <- Repo.one(query) do
      user
    else
      _ -> nil
    end
  end

  @doc """
  Logs the user in by magic link.

  There are two cases to consider:

  1. The user has already confirmed their email. They are logged in
     and the magic link is expired.

  2. The user has not confirmed their email. In this case, the user gets
     confirmed, logged in, and all tokens - including session ones - are
     expired. In theory, no other tokens exist but we delete all of them
     for best security practices.
  """
  def login_user_by_magic_link(token) do
    {:ok, query} = UserToken.verify_magic_link_token_query(token)

    case Repo.one(query) do
      {%User{confirmed_at: nil} = user, _token} ->
        user
        |> User.confirm_changeset()
        |> update_user_and_delete_all_tokens()

      {user, token} ->
        Repo.delete!(token)
        {:ok, {user, []}}

      nil ->
        {:error, :not_found}
    end
  end

  @doc ~S"""
  Delivers the update email instructions to the given user.

  ## Examples

      iex> deliver_user_update_email_instructions(user, current_email, &url(~p"/admin/einstellungen/confirm-email/#{&1}"))
      {:ok, %{to: ..., body: ...}}

  """
  def deliver_user_update_email_instructions(%User{} = user, current_email, update_email_url_fun)
      when is_function(update_email_url_fun, 1) do
    {encoded_token, user_token} = UserToken.build_email_token(user, "change:#{current_email}")

    Repo.insert!(user_token)
    UserNotifier.deliver_update_email_instructions(user, update_email_url_fun.(encoded_token))
  end

  @doc """
  Delivers the magic link login instructions to the given user.
  """
  def deliver_login_instructions(%User{} = user, magic_link_url_fun)
      when is_function(magic_link_url_fun, 1) do
    {encoded_token, user_token} = UserToken.build_email_token(user, "login")
    Repo.insert!(user_token)
    UserNotifier.deliver_login_instructions(user, magic_link_url_fun.(encoded_token))
  end

  @doc """
  Delivers the invitation to a freshly invited user: a magic link for the first login
  that stays valid longer than a regular one (see `UserToken`). Single use like any
  magic link — the first login consumes it.
  """
  def deliver_invite_instructions(%User{} = user, magic_link_url_fun)
      when is_function(magic_link_url_fun, 1) do
    {encoded_token, user_token} = UserToken.build_email_token(user, "invite")
    Repo.insert!(user_token)
    UserNotifier.deliver_invite_instructions(user, magic_link_url_fun.(encoded_token))
  end

  @doc """
  Deletes the signed token with the given context.
  """
  def delete_user_session_token(token) do
    Repo.delete_all(from(UserToken, where: [token: ^token, context: "session"]))
    :ok
  end

  @doc """
  Deletes all session tokens for a user (log out everywhere). Returns the deleted
  tokens so callers can drop the live sockets via `UserAuth.disconnect_sessions/1`.
  Scoped to the "session" context so email-change / magic-link tokens are untouched.
  """
  def delete_all_user_session_tokens(%User{} = user) do
    tokens = list_user_session_tokens(user)
    Repo.delete_all(from(t in UserToken, where: t.id in ^Enum.map(tokens, & &1.id)))
    tokens
  end

  @doc """
  Lists a user's session tokens without deleting them, e.g. to drop their live sockets
  via `UserAuth.disconnect_sessions/1` so they remount with fresh privileges.
  """
  def list_user_session_tokens(%User{} = user),
    do: Repo.all(from(t in UserToken, where: t.user_id == ^user.id and t.context == "session"))

  ## Token helper

  defp update_user_and_delete_all_tokens(changeset) do
    Repo.transact(fn ->
      with {:ok, user} <- Repo.update(changeset) do
        tokens_to_expire = Repo.all_by(UserToken, user_id: user.id)

        Repo.delete_all(from(t in UserToken, where: t.id in ^Enum.map(tokens_to_expire, & &1.id)))

        {:ok, {user, tokens_to_expire}}
      end
    end)
  end
end
