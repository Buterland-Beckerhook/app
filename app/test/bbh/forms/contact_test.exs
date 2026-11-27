defmodule Bbh.Forms.ContactTest do
  use ExUnit.Case, async: true

  alias Bbh.Forms.Contact

  @valid %{
    "name" => "  Max Mustermann  ",
    "email" => " max@example.com ",
    "message" => "  Hallo Welt  "
  }

  describe "validate/1" do
    test "accepts valid params and trims fields" do
      assert {:ok, data} = Contact.validate(@valid)
      assert data == %{name: "Max Mustermann", email: "max@example.com", message: "Hallo Welt"}
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

    test "asks for no privacy consent — the form only points to the privacy policy" do
      assert {:ok, _} = Contact.validate(@valid)
      assert {:ok, _} = Contact.validate(Map.put(@valid, "privacy", "true"))
    end

    test "collects multiple errors at once" do
      assert {:error, errors} = Contact.validate(%{})
      assert Map.has_key?(errors, :name)
      assert Map.has_key?(errors, :email)
      assert Map.has_key?(errors, :message)
      refute Map.has_key?(errors, :privacy)
    end
  end
end
