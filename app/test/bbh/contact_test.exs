defmodule Bbh.ContactTest do
  use ExUnit.Case, async: true

  import Swoosh.TestAssertions

  alias Bbh.Contact

  @valid %{
    "name" => "  Max Mustermann  ",
    "email" => " max@example.com ",
    "message" => "  Hallo Welt  ",
    "privacy" => "true"
  }

  describe "validate/1" do
    test "accepts valid params and trims fields" do
      assert {:ok, data} = Contact.validate(@valid)
      assert data == %{name: "Max Mustermann", email: "max@example.com", message: "Hallo Welt"}
    end

    test "accepts alternative consent truthy values" do
      assert {:ok, _} = Contact.validate(%{@valid | "privacy" => "on"})
      assert {:ok, _} = Contact.validate(%{@valid | "privacy" => "1"})
    end

    test "requires a name" do
      assert {:error, %{name: _}} = Contact.validate(%{@valid | "name" => "   "})
    end

    test "requires a valid email" do
      assert {:error, %{email: _}} = Contact.validate(%{@valid | "email" => "not-an-email"})
    end

    test "requires a message" do
      assert {:error, %{message: _}} = Contact.validate(%{@valid | "message" => ""})
    end

    test "requires privacy consent" do
      assert {:error, %{privacy: _}} = Contact.validate(Map.delete(@valid, "privacy"))
    end

    test "collects multiple errors at once" do
      assert {:error, errors} = Contact.validate(%{})
      assert Map.has_key?(errors, :name)
      assert Map.has_key?(errors, :email)
      assert Map.has_key?(errors, :message)
      assert Map.has_key?(errors, :privacy)
    end
  end

  describe "deliver/1" do
    test "sends an email to the club inbox with the sender as reply-to" do
      {:ok, data} = Contact.validate(@valid)
      assert {:ok, _} = Contact.deliver(data)

      assert_email_sent(fn email ->
        assert email.from == {"Website Kontaktformular", "noreply@buterland-beckerhook.de"}
        assert email.reply_to == {"Max Mustermann", "max@example.com"}
        assert email.subject =~ "Max Mustermann"
        assert email.text_body =~ "Hallo Welt"
      end)
    end
  end
end
