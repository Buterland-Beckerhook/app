defmodule Bbh.Calendar.Location do
  @moduledoc "Event venue (Veranstaltungsort)."
  use Bbh.Schema

  schema "locations" do
    field :key, :string
    field :name, :string
    field :street, :string
    field :zip, :string
    field :city, :string
    field :lat, :float
    field :lng, :float
    field :url, :string
    field :maps_url, :string

    has_many :events, Bbh.Calendar.Event

    timestamps()
  end

  @doc false
  def changeset(location, attrs) do
    location
    |> cast(attrs, [:key, :name, :street, :zip, :city, :lat, :lng, :url, :maps_url])
    |> validate_required([:key, :name])
    |> unique_constraint(:key)
  end
end
