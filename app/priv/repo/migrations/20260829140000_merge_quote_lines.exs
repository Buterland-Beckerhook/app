defmodule Bbh.Repo.Migrations.MergeQuoteLines do
  use Ecto.Migration

  # Every column whose content goes through `Bbh.Html.sanitize/1` on write.
  @targets [
    {"block_richtext", "body"},
    {"block_alert", "body"},
    {"block_media_card", "body"},
    {"articles", "body"},
    {"events", "body"},
    {"people", "biography"},
    {"site_settings", "home_notice_text"}
  ]

  # Quill emits one `<blockquote>` per line, so a multi-line quote was stored — and
  # rendered — as a stack of separate quote boxes. `Bbh.Html.sanitize/1` now merges
  # such a run into a single quote whose lines are joined by `<br />`; re-run it over
  # the rows that hold a quote so existing content is fixed without a manual re-save.
  # Only rows the sanitizer actually changes are written, and `updated_at` is left
  # alone — this is a formatting repair, not an edit. Irreversible (the merged quote
  # is indistinguishable from one an author wrote that way), so `down` is a no-op.
  def up do
    for {table, column} <- @targets do
      %{rows: rows} =
        repo().query!("SELECT id, #{column} FROM #{table} WHERE #{column} LIKE '%</blockquote>%'")

      for [id, html] <- rows, merged = Bbh.Html.sanitize(html), merged != html do
        repo().query!("UPDATE #{table} SET #{column} = $1 WHERE id = $2", [merged, id])
      end
    end
  end

  def down, do: :ok
end
