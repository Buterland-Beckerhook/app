defmodule Bbh.MailerTest do
  # async: false — this suite mutates the global Logger level (to capture the
  # info-level send logs) and the global mailer config (to exercise the failure
  # and crash branches with stub adapters); neither may race other tests.
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog
  import Swoosh.Email
  import Swoosh.TestAssertions

  alias Bbh.Mailer

  # --- Stub adapters exercising each delivery outcome ------------------------

  defmodule FailingAdapter do
    def deliver(_email, _config), do: {:error, :nxdomain}
    def deliver_many(_emails, _config), do: {:error, :nxdomain}
    def validate_config(_config), do: :ok
  end

  defmodule RaisingAdapter do
    def deliver(_email, _config), do: raise("boom")
    def deliver_many(_emails, _config), do: raise("boom")
    def validate_config(_config), do: :ok
  end

  defmodule ExitingAdapter do
    def deliver(_email, _config), do: exit({:timeout, :simulated})
    def deliver_many(_emails, _config), do: exit({:timeout, :simulated})
    def validate_config(_config), do: :ok
  end

  setup do
    prev_level = Logger.level()
    prev_cfg = Application.get_env(:bbh, Bbh.Mailer)
    Logger.configure(level: :info)

    on_exit(fn ->
      Logger.configure(level: prev_level)
      Application.put_env(:bbh, Bbh.Mailer, prev_cfg)
    end)

    :ok
  end

  defp sample_email do
    new()
    |> to("someone@example.com")
    |> from({"Bbh", "noreply@example.com"})
    |> subject("Hallo")
    |> text_body("Body")
  end

  describe "deliver_logged/2 success" do
    test "delivers the email and logs the attempt and the success" do
      log =
        capture_log(fn ->
          assert {:ok, _meta} = Mailer.deliver_logged(sample_email(), "contact")
        end)

      assert_email_sent(subject: "Hallo")
      assert log =~ "[mail:contact] sending"
      assert log =~ "[mail:contact] delivered"
      assert log =~ "someone@example.com"
    end

    test "defaults the context label to \"mail\"" do
      log = capture_log(fn -> Mailer.deliver_logged(sample_email()) end)
      assert log =~ "[mail:mail] sending"
    end

    test "never logs the SMTP credentials, only the relay host" do
      Application.put_env(:bbh, Bbh.Mailer,
        adapter: Swoosh.Adapters.Test,
        relay: "mail.example.test",
        username: "smtp-user",
        password: "sup3r-s3cret-pw"
      )

      log = capture_log(fn -> Mailer.deliver_logged(sample_email(), "contact") end)

      assert log =~ "relay=\"mail.example.test\""
      refute log =~ "sup3r-s3cret-pw"
      refute log =~ "smtp-user"
    end
  end

  describe "sender/0 and sender_name/0" do
    test "fall back to the club defaults when unconfigured" do
      Application.delete_env(:bbh, :contact_sender)
      Application.delete_env(:bbh, :contact_sender_name)

      assert Mailer.sender() == "noreply@buterland-beckerhook.de"
      assert Mailer.sender_name() == "Buterland-Beckerhook.de"
    end

    test "read overrides from application config" do
      Application.put_env(:bbh, :contact_sender, "override@example.test")
      Application.put_env(:bbh, :contact_sender_name, "Override Name")

      on_exit(fn ->
        Application.delete_env(:bbh, :contact_sender)
        Application.delete_env(:bbh, :contact_sender_name)
      end)

      assert Mailer.sender() == "override@example.test"
      assert Mailer.sender_name() == "Override Name"
    end
  end

  describe "deliver_logged/2 failure" do
    test "logs the relay and exact reason and returns the error tuple" do
      Application.put_env(:bbh, Bbh.Mailer, adapter: FailingAdapter, relay: "mail.example.test")

      log =
        capture_log(fn ->
          assert {:error, :nxdomain} = Mailer.deliver_logged(sample_email(), "contact")
        end)

      assert log =~ "[mail:contact] delivery FAILED"
      assert log =~ "relay=\"mail.example.test\""
      assert log =~ "reason=:nxdomain"
    end

    test "catches a raising adapter, logs it, and returns an error tuple" do
      Application.put_env(:bbh, Bbh.Mailer, adapter: RaisingAdapter, relay: "mail.example.test")

      log =
        capture_log(fn ->
          assert {:error, {:exception, %RuntimeError{}}} =
                   Mailer.deliver_logged(sample_email(), "contact")
        end)

      assert log =~ "[mail:contact] delivery raised"
      assert log =~ "relay=\"mail.example.test\""
    end

    test "catches an exiting adapter (e.g. SMTP connect timeout) instead of crashing" do
      Application.put_env(:bbh, Bbh.Mailer, adapter: ExitingAdapter, relay: "mail.example.test")

      log =
        capture_log(fn ->
          assert {:error, {:exit, {:timeout, :simulated}}} =
                   Mailer.deliver_logged(sample_email(), "contact")
        end)

      assert log =~ "[mail:contact] delivery crashed"
      assert log =~ "relay=\"mail.example.test\""
    end
  end
end
