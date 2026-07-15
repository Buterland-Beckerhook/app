defmodule Bbh.AccountsFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `Bbh.Accounts` context.
  """

  import Ecto.Query

  alias Bbh.Accounts
  alias Bbh.Accounts.Scope

  def unique_user_email, do: "user#{System.unique_integer()}@example.com"

  def valid_user_attributes(attrs \\ %{}) do
    Enum.into(attrs, %{
      email: unique_user_email()
    })
  end

  def unconfirmed_user_fixture(attrs \\ %{}) do
    {:ok, user} =
      attrs
      |> valid_user_attributes()
      |> Accounts.register_user()

    user
  end

  def user_fixture(attrs \\ %{}) do
    user = unconfirmed_user_fixture(attrs)

    token =
      extract_user_token(fn url ->
        Accounts.deliver_login_instructions(user, url)
      end)

    {:ok, {user, _expired_tokens}} =
      Accounts.login_user_by_magic_link(token)

    user
  end

  def admin_user_fixture(attrs \\ %{}) do
    user = user_fixture(attrs)
    {:ok, user} = Accounts.update_user_role(user, "admin")
    user
  end

  def user_scope_fixture do
    user = user_fixture()
    user_scope_fixture(user)
  end

  def user_scope_fixture(user) do
    Scope.for_user(user)
  end

  @doc "Inserts a passkey credential for the given user."
  def passkey_fixture(user, attrs \\ %{}) do
    attrs =
      Enum.into(attrs, %{
        credential_id: :crypto.strong_rand_bytes(16),
        public_key: %{
          1 => 2,
          3 => -7,
          -1 => 1,
          -2 => :crypto.strong_rand_bytes(32),
          -3 => :crypto.strong_rand_bytes(32)
        },
        aaguid: <<0::128>>,
        sign_count: 0,
        nickname: "Test Passkey"
      })

    %Bbh.Accounts.UserPasskey{}
    |> Bbh.Accounts.UserPasskey.changeset(Map.put(attrs, :user_id, user.id))
    |> Bbh.Repo.insert!()
  end

  def extract_user_token(fun) do
    {:ok, captured_email} = fun.(&"[TOKEN]#{&1}[TOKEN]")
    [_, token | _] = String.split(captured_email.text_body, "[TOKEN]")
    token
  end

  def override_token_authenticated_at(token, authenticated_at) when is_binary(token) do
    Bbh.Repo.update_all(
      from(t in Accounts.UserToken,
        where: t.token == ^token
      ),
      set: [authenticated_at: authenticated_at]
    )
  end

  def generate_user_magic_link_token(user) do
    {encoded_token, user_token} = Accounts.UserToken.build_email_token(user, "login")
    Bbh.Repo.insert!(user_token)
    {encoded_token, user_token.token}
  end

  def offset_user_token(token, amount_to_add, unit) do
    dt = DateTime.add(DateTime.utc_now(:second), amount_to_add, unit)

    Bbh.Repo.update_all(
      from(ut in Accounts.UserToken, where: ut.token == ^token),
      set: [inserted_at: dt, authenticated_at: dt]
    )
  end
end
