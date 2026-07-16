defmodule Bbh.Club.Person do
  @moduledoc "Board member / officer / historical figure."
  use Bbh.Schema

  @roles ~w(oberst oberstleutnant major praesident vizepraesident geschaeftsfuehrer
            schriftfuehrer kassierer vorstand offizier jungschuetzensprecher mitglied)

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
    "mitglied" => "Mitglied"
  }

  def roles, do: @roles
  def vorstand_roles, do: @vorstand_roles
  def offiziere_roles, do: @offiziere_roles
  def role_label(role), do: Map.get(@role_labels, role, role)

  schema "people" do
    field :name, :string
    field :role, :string
    field :email, :string
    field :honorary_member, :boolean, default: false
    field :street, :string
    field :city, :string
    field :birth_date, :string
    field :death_date, :string
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
      :honorary_member,
      :street,
      :city,
      :birth_date,
      :death_date,
      :year_start,
      :year_end,
      :biography,
      :sort_order,
      :portrait_id
    ])
    |> validate_required([:name, :role])
    |> validate_inclusion(:role, @roles)
    |> validate_format(:email, ~r/^[^\s@]+@[^\s@]+\.[^\s@]+$/,
      message: "muss eine gültige E-Mail-Adresse sein"
    )
    |> validate_number(:sort_order, greater_than_or_equal_to: 0)
    |> foreign_key_constraint(:portrait_id)
    |> check_constraint(:sort_order,
      name: :people_sort_order_nonneg,
      message: "darf nicht negativ sein"
    )
  end
end
