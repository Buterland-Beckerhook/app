defmodule Bbh.Club.Person do
  @moduledoc "Board member / officer / historical figure."
  use Bbh.Schema

  @roles ~w(oberst oberstleutnant major praesident vizepraesident geschaeftsfuehrer
            schriftfuehrer kassierer vorstand offizier jungschuetzensprecher mitglied)

  @vorstand_roles ~w(praesident vizepraesident geschaeftsfuehrer schriftfuehrer kassierer vorstand)
  @offiziere_roles ~w(oberst oberstleutnant major offizier)

  def roles, do: @roles
  def vorstand_roles, do: @vorstand_roles
  def offiziere_roles, do: @offiziere_roles

  schema "people" do
    field :name, :string
    field :role, :string
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
    |> validate_number(:sort_order, greater_than_or_equal_to: 0)
  end
end
