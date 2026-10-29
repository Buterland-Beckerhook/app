defmodule Bbh.Repo.Migrations.CreateTicketQueues do
  use Ecto.Migration

  # Postfach queues move from code to the database, maintained in the admin
  # (Bbh.Tickets.Queue). Seeded with the queues the code had. `key` is what tickets
  # and grants refer to, so it never changes.
  def up do
    create table(:ticket_queues, primary_key: false) do
      add :key, :string, primary_key: true
      add :label, :string, null: false
      add :inbound_address, :string
      add :reply_address, :string
      add :signature, :string
      add :in_contact_form, :boolean, null: false, default: false
      add :position, :integer, null: false, default: 0
      add :active, :boolean, null: false, default: true
      timestamps(type: :utc_datetime)
    end

    create unique_index(:ticket_queues, ["lower(inbound_address)"],
             name: :ticket_queues_inbound_address_index
           )

    # The table must exist before the seed rows go in (migration commands are queued).
    flush()

    domain = "buterland-beckerhook.de"

    rows = [
      # key, label, inbound local part, reply local part, signature, contact form
      {"info", "Allgemein", "info", nil, nil, true},
      {"vorstand", "Vorstand", "vorstand", nil, "Vorstand", true},
      {"offiziere", "Offiziere", "offiziere", nil, "Offiziere", true},
      {"jungschuetzen", "Jungschützen", "jungschuetzen", nil, "Jungschützen", true},
      {"kinderfest", "Kinderfestausschuss", "kinderfestausschuss", nil, "Kinderfestausschuss",
       true},
      {"webmaster", "Website", "webmaster", nil, "Website", false},
      # Membership applications come from the form only and are answered by the Vorstand.
      {"mitgliedschaft", "Mitgliedsanträge", nil, "vorstand", "Vorstand", false}
    ]

    for {{key, label, inbound, reply, signature, contact}, position} <- Enum.with_index(rows) do
      address = fn
        nil -> nil
        local -> "#{local}@#{domain}"
      end

      repo().insert_all("ticket_queues", [
        %{
          key: key,
          label: label,
          inbound_address: address.(inbound),
          reply_address: address.(reply),
          signature: signature,
          in_contact_form: contact,
          position: position,
          active: true,
          inserted_at: DateTime.utc_now(:second),
          updated_at: DateTime.utc_now(:second)
        }
      ])
    end
  end

  def down do
    drop table(:ticket_queues)
  end
end
