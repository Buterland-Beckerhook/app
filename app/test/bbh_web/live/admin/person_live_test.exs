defmodule BbhWeb.Admin.PersonLiveTest do
  use BbhWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Bbh.ClubFixtures
  import Bbh.ContentFixtures, only: [upload_fixture: 1]

  alias Bbh.Club

  setup :register_and_log_in_admin

  describe "Index" do
    test "lists people", %{conn: conn} do
      person = person_fixture(name: "Anna Beispiel")
      {:ok, _lv, html} = live(conn, ~p"/admin/personen")

      assert html =~ "Personen"
      assert html =~ person.name
    end

    test "deletes a person from the edit page with name confirmation", %{conn: conn} do
      person = person_fixture()
      {:ok, lv, _html} = live(conn, ~p"/admin/personen/#{person.id}/bearbeiten")

      {:ok, _lv, html} =
        lv
        |> form("form[phx-submit=delete]", confirm: person.name)
        |> render_submit()
        |> follow_redirect(conn, ~p"/admin/personen")

      assert html =~ "Person gelöscht"
      assert_raise Ecto.NoResultsError, fn -> Club.get_person!(person.id) end
    end
  end

  describe "Form (new)" do
    test "creates a person and redirects", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/admin/personen/neu")

      {:ok, _lv, html} =
        lv
        |> form("#person-form", person: %{name: "Klaus Vorstand", role: "vorstand"})
        |> render_submit()
        |> follow_redirect(conn, ~p"/admin/personen")

      assert html =~ "Klaus Vorstand"
    end
  end

  describe "Portrait" do
    # The shared picker (BbhWeb.Admin.MediaPicker) owns its own state, so it is driven
    # through its own elements; a pick reaches the form LiveView as a message, hence the
    # render/1 to synchronize before asserting.
    defp pick_portrait(lv, media_id) do
      lv |> element(~s(button[phx-value-context="portrait"])) |> render_click()
      lv |> element(~s(#media-picker button[phx-value-id="#{media_id}"])) |> render_click()
      render(lv)
    end

    test "a portrait picked while creating survives the save", %{conn: conn} do
      upload = upload_fixture(filename: "heinrich.webp")
      {:ok, lv, _html} = live(conn, ~p"/admin/personen/neu")

      html = pick_portrait(lv, upload.id)

      # Picking a picture puts `action: :validate` on the changeset, the same as the
      # validate event does. On an untouched form that must not light up every required
      # field — `used_input?/1` gates errors per field, and nothing has been typed yet.
      refute html |> LazyHTML.from_document() |> LazyHTML.query("p.text-error") |> Enum.any?()

      {:ok, _lv, _html} =
        lv
        |> form("#person-form", person: %{name: "Heinrich Meyer", role: "vorstand"})
        |> render_submit()
        |> follow_redirect(conn, ~p"/admin/personen")

      person = Bbh.Repo.get_by!(Bbh.Club.Person, name: "Heinrich Meyer")
      assert person.portrait_id == upload.id
    end

    test "a portrait can be changed and removed again on an existing person", %{conn: conn} do
      first = upload_fixture(filename: "alt.webp")
      second = upload_fixture(filename: "neu.webp")
      person = person_fixture(name: "Karl Bauer", portrait_id: first.id)

      {:ok, lv, _html} = live(conn, ~p"/admin/personen/#{person.id}/bearbeiten")
      # The stored portrait shows as a thumbnail, so the editor can see what is set.
      assert has_element?(lv, ~s(#person-form img[src*="#{first.storage_key}"]))
      refute has_element?(lv, ~s(#person-form fieldset span), "Kein Bild")

      pick_portrait(lv, second.id)

      lv
      |> form("#person-form", person: %{name: "Karl Bauer", role: person.role})
      |> render_submit()

      assert Club.get_person!(person.id).portrait_id == second.id

      {:ok, lv, _html} = live(conn, ~p"/admin/personen/#{person.id}/bearbeiten")
      lv |> element(~s(button[phx-click="clear_portrait"])) |> render_click()

      lv
      |> form("#person-form", person: %{name: "Karl Bauer", role: person.role})
      |> render_submit()

      assert is_nil(Club.get_person!(person.id).portrait_id)
    end

    test "the pick survives a later phx-change, without being restated", %{conn: conn} do
      upload = upload_fixture(filename: "bleibt.webp")
      {:ok, lv, _html} = live(conn, ~p"/admin/personen/neu")

      pick_portrait(lv, upload.id)

      # This is the assertion the hidden `person[portrait_id]` input exists for: typing
      # after the pick fires phx-change, which rebuilds the changeset purely from params.
      # Without the hidden input the portrait would be dropped here, silently.
      lv |> form("#person-form", person: %{name: "Heinrich Meyer"}) |> render_change()

      {:ok, _lv, _html} =
        lv
        |> form("#person-form", person: %{role: "vorstand"})
        |> render_submit()
        |> follow_redirect(conn, ~p"/admin/personen")

      assert Bbh.Repo.get_by!(Bbh.Club.Person, name: "Heinrich Meyer").portrait_id == upload.id
    end

    test "a failed save keeps the picked portrait on the re-rendered form", %{conn: conn} do
      upload = upload_fixture(filename: "ueberlebt.webp")
      {:ok, lv, _html} = live(conn, ~p"/admin/personen/neu")

      pick_portrait(lv, upload.id)

      # `name` is required, so this comes back as {:error, changeset} rather than redirecting.
      html = lv |> form("#person-form", person: %{name: ""}) |> render_submit()

      assert html =~ "person-form"
      assert has_element?(lv, ~s(#person-form img[src*="#{upload.storage_key}"]))

      assert [value] =
               html
               |> LazyHTML.from_document()
               |> LazyHTML.query(~s(input[type="hidden"][name="person[portrait_id]"]))
               |> LazyHTML.attribute("value")

      assert value == upload.id
    end

    test "every picker button on this form has a matching handler", %{conn: conn} do
      person = person_fixture()
      upload = upload_fixture(filename: "irgendwas.webp")

      {:ok, lv, html} = live(conn, ~p"/admin/personen/#{person.id}/bearbeiten")

      buttons =
        html
        |> LazyHTML.from_document()
        |> LazyHTML.query(~s([phx-target="#media-picker"][phx-click="open"]))
        |> LazyHTML.attribute("phx-value-context")

      # A canary: bump this only together with a new handle_info clause in the form.
      # (The rich-text toolbar's picker button is added by the QuillEditor JS hook and
      # is handled inside the picker, so it never appears here.)
      assert buttons == ["portrait"]

      # An unhandled context would raise FunctionClauseError in handle_info/2 and kill
      # the LiveView, so surviving a pick from every button *is* the assertion.
      for context <- buttons do
        lv |> element(~s(button[phx-value-context="#{context}"])) |> render_click()
        lv |> element(~s(#media-picker button[phx-value-id="#{upload.id}"])) |> render_click()
        assert render(lv) =~ "Person bearbeiten"
      end
    end
  end
end
