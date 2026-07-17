defmodule Bbh.Accounts.UserNotifierTest do
  use ExUnit.Case, async: false

  import Swoosh.TestAssertions

  alias Bbh.Accounts.User
  alias Bbh.Accounts.UserNotifier

  @user %User{email: "member@buterland-beckerhook.de", confirmed_at: ~U[2026-01-01 00:00:00Z]}

  describe "from address" do
    test "uses the configured :contact_sender so the SMTP user owns it" do
      previous = Application.get_env(:bbh, :contact_sender)
      # A sentinel distinct from the fallback default, so this only passes if
      # the config is genuinely read (not if sender/0 regressed to a literal).
      Application.put_env(:bbh, :contact_sender, "custom-sender@example.test")
      on_exit(fn -> restore(:contact_sender, previous) end)

      {:ok, _} = UserNotifier.deliver_login_instructions(@user, "https://example.test/login")

      assert_email_sent(fn email ->
        assert email.from == {"Buterland-Beckerhook.de", "custom-sender@example.test"}
      end)
    end

    test "falls back to the club default when :contact_sender is unset" do
      previous = Application.get_env(:bbh, :contact_sender)
      Application.delete_env(:bbh, :contact_sender)
      on_exit(fn -> restore(:contact_sender, previous) end)

      {:ok, _} =
        UserNotifier.deliver_update_email_instructions(@user, "https://example.test/email")

      assert_email_sent(fn email ->
        assert email.from == {"Buterland-Beckerhook.de", "noreply@buterland-beckerhook.de"}
      end)
    end
  end

  defp restore(_key, nil), do: :ok
  defp restore(key, value), do: Application.put_env(:bbh, key, value)
end
