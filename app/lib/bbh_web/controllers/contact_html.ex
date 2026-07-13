defmodule BbhWeb.ContactHTML do
  use BbhWeb, :html

  embed_templates "contact_html/*"

  @doc "Error message for a field, if any."
  def error_for(errors, field), do: Map.get(errors, field)

  @doc "Prior value for a field on re-render."
  def value_for(params, field), do: Map.get(params, field, "")
end
