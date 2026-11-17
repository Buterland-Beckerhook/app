defmodule Bbh.Accounts do
  @moduledoc """
  The Accounts context.
  """

  import Ecto.Query, warn: false
  require Logger
  alias Bbh.Repo

  alias Bbh.Accounts.{User, UserToken, UserNotifier}

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

  @doc "A user by id, or `nil` — for a reference that may have gone since."
  def get_user(id), do: Repo.get(User, id)

  @doc "The users with these ids; ids without a user are skipped."
  def list_users_by_ids(ids), do: Repo.all(from u in User, where: u.id in ^ids)

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

  @doc "The users holding the admin role, by email."
  def list_admins, do: Repo.all(from u in User, where: u.role == "admin", order_by: u.email)

  @doc "How many users currently hold the admin role."
  def count_admins, do: Repo.aggregate(from(u in User, where: u.role == "admin"), :count)

  def delete_user(%User{} = user), do: Repo.delete(user)

  @doc """
  Schedule the user's deletion for `date` (a `Date`, an ISO-8601 string, or nil/""
  to cancel). The date must lie in the future.
  """
  def schedule_user_deletion(%User{} = user, date) do
    date = if date == "", do: nil, else: date

    user
    |> User.delete_on_changeset(%{delete_on: date}, Bbh.Time.real_today())
    |> Repo.update()
  end

  @doc """
  Delete every user whose `delete_on` is `today` or earlier. The last admin is kept
  (and logged), so the site can't lock itself out. Returns `[{user, session_tokens}]`
  of the deleted users — the caller drops their live sockets.
  """
  def delete_due_users(%Date{} = today) do
    from(u in User, where: u.delete_on <= ^today, order_by: u.email)
    |> Repo.all()
    |> Enum.flat_map(fn user ->
      if user.role == "admin" and count_admins() <= 1 do
        Logger.warning("Scheduled deletion of #{user.email} skipped: last admin")
        []
      else
        tokens = list_user_session_tokens(user)

        case delete_user(user) do
          {:ok, _} ->
            [{user, tokens}]

          {:error, changeset} ->
            Logger.error("Scheduled deletion of #{user.email} failed: #{inspect(changeset)}")
            []
        end
      end
    end)
  end

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
  Deletes every session token of the user except `keep` (the caller's own session) —
  after a change to the sign-in methods, so no session established under the old ones
  survives elsewhere. Returns the deleted tokens for `UserAuth.disconnect_sessions/1`.
  """
  def delete_other_user_session_tokens(%User{} = user, keep) when is_binary(keep) do
    tokens = user |> list_user_session_tokens() |> Enum.reject(&(&1.token == keep))
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
