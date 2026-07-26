defmodule BbhWeb.MembershipHTML do
  use BbhWeb, :html

  embed_templates "membership_html/*"

  @doc "Error message for a field, if any."
  def error_for(errors, field), do: Map.get(errors, field)

  @doc "Prior value for a field on re-render."
  def value_for(params, field), do: Map.get(params, field, "")

  @doc "Prior value for the nth entry of an array field (e.g. children) on re-render."
  def value_at(params, field, index) do
    case Map.get(params, field) do
      list when is_list(list) -> Enum.at(list, index, "")
      _ -> ""
    end
  end

  @doc """
  Row indices to render for the "Kinder unter 15 Jahren" section: every submitted row
  plus one trailing empty row. JS appends further rows client-side; on a re-render this
  reproduces what was submitted (see `assets/js/membership.js`).
  """
  def child_row_indices(params) do
    count = max(array_length(params, "kind_vorname"), array_length(params, "kind_geburtsdatum"))
    0..count
  end

  defp array_length(params, field) do
    case Map.get(params, field) do
      list when is_list(list) -> length(list)
      _ -> 0
    end
  end
end
