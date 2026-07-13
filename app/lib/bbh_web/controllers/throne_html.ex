defmodule BbhWeb.ThroneHTML do
  use BbhWeb, :html

  embed_templates "throne_html/*"

  @doc "The throne picture for a throne (its article image flagged use_as_throne_picture)."
  def throne_picture(%{article: %{images: images}}) when is_list(images) do
    Enum.find(images, & &1.use_as_throne_picture) || List.first(images)
  end

  def throne_picture(_), do: nil
end
