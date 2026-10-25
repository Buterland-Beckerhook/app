defmodule Bbh.Club.Person do
  @moduledoc "Board member / officer / historical figure."
  use Bbh.Schema

  @roles ~w(oberst oberstleutnant major praesident vizepraesident geschaeftsfuehrer
            schriftfuehrer kassierer vorstand offizier jungschuetzensprecher mitglied
            verantwortlich)

  @vorstand_roles ~w(praesident vizepraesident geschaeftsfuehrer schriftfuehrer kassierer vorstand)
  @offiziere_roles ~w(oberst oberstleutnant major offizier)

  @role_labels %{
    "oberst" => "Oberst",
    "oberstleutnant" => "Oberstleutnant",
    "major" => "Major",
    "praesident" => "Präsident",
    "vizepraesident" => "Vizepräsident",
    "geschaeftsfuehrer" => "Geschäftsführer",
    "schriftfuehrer" => "Schriftführer",
    "kassierer" => "Kassierer",
    "vorstand" => "Vorstand",
    "offizier" => "Offizier",
    "jungschuetzensprecher" => "Jungschützensprecher",
    "mitglied" => "Mitglied",
    # Spelled out in full: the Impressum renders it via `{{ verantwortlich.role }}`.
    "verantwortlich" => "Verantwortlich für den Inhalt nach § 18 Abs. 2 MStV"
  }

  @unknown_honorary_year 1900

  def roles, do: @roles
  def vorstand_roles, do: @vorstand_roles
  def offiziere_roles, do: @offiziere_roles
  def role_label(role), do: Map.get(@role_labels, role, role)

  @doc "The placeholder `honorary_since` for an Ehrenmitglied whose year is unknown."
  def unknown_honorary_year, do: @unknown_honorary_year

  @doc "The appointment year worth showing, or nil (not honorary, or year unknown)."
  def honorary_year(%{honorary_since: @unknown_honorary_year}), do: nil
  def honorary_year(%{honorary_since: year}), do: year

  schema "people" do
    field :name, :string
    field :role, :string
    field :email, :string
    # Year of appointment as Ehrenmitglied; set means honorary member. 1900 stands for
    # "appointed, year unknown" and is never rendered (see `honorary_year/1`).
    field :honorary_since, :integer
    field :street, :string
    field :city, :string
    field :birth_date, :date
    field :birth_place, :string
    # Set means deceased — the Ehrenmitglieder list splits on it.
    field :death_date, :date
    field :death_place, :string
    field :year_start, :integer
    field :year_end, :integer
    field :biography, :string
    field :sort_order, :integer, default: 0

    belongs_to :portrait, Bbh.Media.Upload

    timestamps()
  end

  @doc false
  def changeset(person, attrs) do
    person
    |> cast(attrs, [
      :name,
      :role,
      :email,
      :honorary_since,
      :street,
      :city,
      :birth_date,
      :birth_place,
      :death_date,
      :death_place,
      :year_start,
      :year_end,
      :biography,
      :sort_order,
      :portrait_id
    ])
    # The Personenliste's „Karten" style renders this through
    # `BbhWeb.Format.render_richtext/1`, whose XSS exemption rests on the stored HTML
    # already being sanitized — same contract as every block body.
    |> update_change(:biography, &Bbh.Html.sanitize/1)
    |> validate_required([:name, :role])
    |> validate_inclusion(:role, @roles)
    |> validate_format(:email, ~r/^[^\s@]+@[^\s@]+\.[^\s@]+$/,
      message: "muss eine gültige E-Mail-Adresse sein"
    )
    |> validate_number(:sort_order, greater_than_or_equal_to: 0)
    |> validate_number(:honorary_since,
      greater_than_or_equal_to: @unknown_honorary_year,
      message:
        "muss ab #{@unknown_honorary_year} liegen (#{@unknown_honorary_year} = Jahr unbekannt)"
    )
    |> check_constraint(:honorary_since, name: :people_honorary_since_range)
    |> foreign_key_constraint(:portrait_id)
    |> check_constraint(:sort_order,
      name: :people_sort_order_nonneg,
      message: "darf nicht negativ sein"
    )
  end
end
