defmodule BbhWeb.ControllerHelpers do
  @moduledoc "Small shared helpers for public controllers."
  import Plug.Conn
  import Phoenix.Controller

  @doc "Render the 404 page and halt."
  def not_found(conn) do
    conn
    |> put_status(:not_found)
    |> put_view(BbhWeb.ErrorHTML)
    |> render(:"404")
    |> halt()
  end

  @doc "Parse the German `?seite=` page param into a positive integer, default 1."
  def page_param(params) do
    case params |> Map.get("seite", "1") |> Integer.parse() do
      {n, _} when n >= 1 -> n
      _ -> 1
    end
  end

  @doc "Parse a 4-digit year path segment, or nil."
  def parse_year(year) do
    case Integer.parse(year) do
      {y, ""} when y >= 1900 -> y
      _ -> nil
    end
  end
end
