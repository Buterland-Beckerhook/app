defmodule Bbh.Repo.Migrations.SeedMembershipPages do
  use Ecto.Migration
  import Ecto.Query

  @moduledoc """
  Seed the two hidden, published content pages whose blocks the membership form
  (`/verein/mitglied-werden`) renders above and below itself:

    * `mitglied-werden-intro` — intro text + SEPA/Jahresbeitrag explanation
    * `mitglied-werden-pdf`   — the "prefer the PDF?" download section

  They carry a single editable richtext block with default German copy, so the form
  works out of the box and everything is editable afterwards through /admin/seiten
  (including inserting the media link to the uploaded Aufnahmeantrag PDF).

  Idempotent: each page is only created if its slug does not already exist, so a
  replay (or a snapshot that already contains them) is a no-op. Schemaless inserts
  keep the migration decoupled from later schema changes.
  """

  @pages [
    {"mitglied-werden-intro", "Mitglied werden – Einleitung",
     """
     <p>Schön, dass Sie Mitglied im Schützenverein Buterland-Beckerhook e.V. werden möchten! Füllen Sie einfach das folgende Formular aus – wir melden uns anschließend bei Ihnen.</p>
     <p>Der aktuelle Jahresbeitrag beträgt <strong>__,__ €</strong> und wird jährlich am 15. März per SEPA-Lastschrift eingezogen. Mit dem Absenden des Formulars erteilen Sie dem Verein ein elektronisches SEPA-Lastschriftmandat; eine Unterschrift ist dafür nicht erforderlich.</p>
     """},
    {"mitglied-werden-pdf", "Mitglied werden – PDF",
     """
     <p>Sie möchten den Antrag lieber auf Papier stellen? Laden Sie den Aufnahmeantrag als PDF herunter, füllen Sie ihn aus und senden Sie ihn unterschrieben an den Verein.</p>
     <p><em>Hinweis für Redakteure: Hier den Link zur PDF-Datei aus der Mediathek einfügen.</em></p>
     """}
  ]

  def up do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    for {slug, title, body} <- @pages, not slug_exists?(slug) do
      # Raw 16-byte binaries — the on-the-wire form of a :binary_id column.
      page_id = Ecto.UUID.bingenerate()
      block_id = Ecto.UUID.bingenerate()
      page_block_id = Ecto.UUID.bingenerate()

      repo().insert_all("pages", [
        %{
          id: page_id,
          status: "published",
          title: title,
          slug: slug,
          parent_id: nil,
          sort_order: 0,
          show_in_menu: false,
          inserted_at: now,
          updated_at: now
        }
      ])

      repo().insert_all("block_richtext", [
        %{
          id: block_id,
          body: Bbh.Html.sanitize(body),
          inserted_at: now,
          updated_at: now
        }
      ])

      repo().insert_all("page_blocks", [
        %{
          id: page_block_id,
          page_id: page_id,
          position: 0,
          block_type: "richtext",
          block_id: block_id,
          inserted_at: now,
          updated_at: now
        }
      ])
    end
  end

  def down do
    slugs = Enum.map(@pages, fn {slug, _title, _body} -> slug end)

    page_ids =
      repo().all(from(p in "pages", where: p.slug in ^slugs, select: p.id))

    if page_ids != [] do
      block_ids =
        repo().all(
          from(pb in "page_blocks",
            where: pb.page_id in ^page_ids and pb.block_type == "richtext",
            select: pb.block_id
          )
        )

      repo().delete_all(from(pb in "page_blocks", where: pb.page_id in ^page_ids))
      repo().delete_all(from(b in "block_richtext", where: b.id in ^block_ids))
      repo().delete_all(from(p in "pages", where: p.id in ^page_ids))
    end
  end

  defp slug_exists?(slug) do
    repo().exists?(from(p in "pages", where: p.slug == ^slug))
  end
end
