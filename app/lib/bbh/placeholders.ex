defmodule Bbh.Placeholders do
  @moduledoc """
  Resolves `{{ rolle.feld }}` placeholders in rendered rich-text against club people.

  Editors can reference the current holder of a role in any rich-text body — e.g. an
  Impressum page containing `Verantwortlich: {{ geschaeftsfuehrer.name }}`. Resolution
  runs at **render time** (after the on-write HTML sanitizer, which leaves `{{ }}` as
  plain text), so it never touches stored content.

  A token has the form `{{ <role>.<field> }}`:

    * `<role>` — one of `Bbh.Club.Person.roles/0` (e.g. `geschaeftsfuehrer`, `praesident`)
    * `<field>` — `name`, `email` or `role` (the German role label)

  The role is resolved to its current holder via `Bbh.Club.role_holder/1`. A valid token
  whose person or field value is missing renders as an empty string. A token with an
  unknown role or field is left untouched, so typos stay visible to the editor.
  """

  alias Bbh.Club
  alias Bbh.Club.Person

  @fields ~w(name email role)

  @token ~r/\{\{\s*([a-zA-Z_]+)\.([a-zA-Z_]+)\s*\}\}/

  @doc "Replace all `{{ role.field }}` tokens in `html`. Passes non-binaries through."
  def render(nil), do: nil

  def render(html) when is_binary(html) do
    Regex.replace(@token, html, fn whole, role, field ->
      case resolve(String.downcase(role), String.downcase(field)) do
        {:ok, value} -> Plug.HTML.html_escape(value)
        :unknown -> whole
      end
    end)
  end

  def render(other), do: other

  defp resolve(role, field) do
    cond do
      role not in Person.roles() -> :unknown
      field not in @fields -> :unknown
      true -> {:ok, field_value(Club.role_holder(role), field)}
    end
  end

  defp field_value(nil, _field), do: ""
  defp field_value(person, "name"), do: person.name || ""
  defp field_value(person, "email"), do: person.email || ""
  defp field_value(person, "role"), do: Person.role_label(person.role)
end
