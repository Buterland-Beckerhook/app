# Seed a small, representative dataset to exercise the schema end to end.
# Run with: mix run priv/repo/seeds.exs  (safe to re-run; no-ops if already seeded)

alias Bbh.Repo
alias Bbh.Media.Upload
alias Bbh.Calendar.{Location, Event}
alias Bbh.Club.Person
alias Bbh.Content.{Article, ArticleImage, Throne, Page, PageBlock}
alias Bbh.Content.Blocks

if Repo.aggregate(Article, :count) == 0 do
  location =
    Repo.insert!(
      Location.changeset(%Location{}, %{
        key: "platz",
        name: "Schützenplatz",
        street: "Am Platz 1",
        zip: "48599",
        city: "Gronau",
        lat: 52.21,
        lng: 7.02
      })
    )

  media =
    Repo.insert!(
      Upload.changeset(%Upload{}, %{
        storage_key: "seed/thron-2024.jpg",
        filename: "thron-2024.jpg",
        content_type: "image/jpeg",
        title: "Königspaar 2024",
        copyright: "Buterland-Beckerhook e.V."
      })
    )

  Repo.insert!(
    Person.changeset(%Person{}, %{
      name: "Max Mustermann",
      role: "praesident",
      sort_order: 0,
      portrait_id: media.id
    })
  )

  article =
    Repo.insert!(
      Article.changeset(%Article{}, %{
        status: "published",
        title: "Thron 2024",
        slug: "thron-2024",
        date_published: ~U[2024-07-13 10:00:00Z],
        author: "Vorstand",
        tags: ["Thron", "Schützenfest"],
        body: "<p>Wir gratulieren dem neuen Königspaar.</p>"
      })
    )

  Repo.insert!(
    Throne.changeset(%Throne{}, %{
      article_id: article.id,
      type: "koenig",
      begin_year: 2024,
      end_year: 2025,
      king_title: "Max I.",
      king: "Max Mustermann",
      queen: "Erika Mustermann"
    })
  )

  Repo.insert!(
    ArticleImage.changeset(%ArticleImage{}, %{
      article_id: article.id,
      media_id: media.id,
      title: "Königspaar",
      use_as_article_image: true,
      use_as_throne_picture: true,
      sort: 0
    })
  )

  Repo.insert!(
    Event.changeset(%Event{}, %{
      status: "published",
      title: "Schützenfest 2026",
      slug: "schuetzenfest",
      starts_at: ~U[2026-08-15 14:00:00Z],
      ends_at: ~U[2026-08-17 22:00:00Z],
      location_id: location.id
    })
  )

  page =
    Repo.insert!(
      Page.changeset(%Page{}, %{status: "published", title: "Über uns", slug: "ueber-uns"})
    )

  richtext =
    Repo.insert!(
      Blocks.RichText.changeset(%Blocks.RichText{}, %{
        body: "<p>Der Schützenverein Buterland-Beckerhook e.V. …</p>"
      })
    )

  Repo.insert!(
    PageBlock.changeset(%PageBlock{}, %{
      page_id: page.id,
      position: 0,
      block_type: "richtext",
      block_id: richtext.id
    })
  )

  IO.puts("Seeded sample data.")
else
  IO.puts("Data already present, skipping seeds.")
end
