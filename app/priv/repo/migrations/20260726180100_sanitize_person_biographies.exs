defmodule Bbh.Repo.Migrations.SanitizePersonBiographies do
  use Ecto.Migration
  import Ecto.Query

  @moduledoc """
  Backfill: run existing `people.biography` values through `Bbh.Html.sanitize/1`.

  `biography` has been editable through the Quill editor for as long as the person form has
  existed, but nothing sanitized it on write until 20260726180000's sibling change to
  `Bbh.Club.Person.changeset/2`. Nothing rendered it either, so that was harmless — the
  Personenliste's new „Karten" style is the first thing to publish it, through
  `BbhWeb.Format.render_richtext/1`.

  That function carries `# sobelow_skip ["XSS.Raw"]`, justified by "the stored HTML is
  already sanitized on write". Fixing only the write path would leave that justification
  false for precisely the rows the feature exists to display, so the existing ones are
  cleaned here, once, at deploy.

  Unlike this repo's other data migrations this one calls application code, because HTML
  sanitization cannot be expressed in SQL. Queried schemaless (`from p in "people"`) so a
  later change to the `Person` schema cannot break a replay from scratch.

  No `down`: sanitization has no inverse, and re-introducing unsanitized markup would not
  be a restore.
  """

  def up do
    rows =
      repo().all(
        from(p in "people",
          where: not is_nil(p.biography) and p.biography != "",
          select: %{id: type(p.id, :binary_id), biography: p.biography}
        )
      )

    cleaned =
      Enum.count(rows, fn %{id: id, biography: html} ->
        case Bbh.Html.sanitize(html) do
          ^html ->
            false

          clean ->
            repo().update_all(from(p in "people", where: p.id == type(^id, :binary_id)),
              set: [biography: clean]
            )

            true
        end
      end)

    if cleaned > 0, do: IO.puts("  * sanitized #{cleaned} of #{length(rows)} biographies")
  end

  def down, do: :ok
end
