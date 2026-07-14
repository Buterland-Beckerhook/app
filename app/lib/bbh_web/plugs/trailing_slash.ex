defmodule BbhWeb.Plugs.TrailingSlash do
  @moduledoc """
  Permanently redirects legacy Hugo URLs (which used trailing slashes, e.g.
  `/aktuell/2024/frauenfest/`) to their slashless equivalents. The route structure
  otherwise matches, so this preserves old links + SEO.
  """
  @behaviour Plug
  import Plug.Conn

  @impl true
  def init(opts), do: opts

  @impl true
  def call(%Plug.Conn{request_path: path} = conn, _opts)
      when path != "/" do
    if String.ends_with?(path, "/") do
      target = String.trim_trailing(path, "/")
      target = if conn.query_string == "", do: target, else: target <> "?" <> conn.query_string

      conn
      |> put_status(:moved_permanently)
      |> Phoenix.Controller.redirect(to: target)
      |> halt()
    else
      conn
    end
  end

  def call(conn, _opts), do: conn
end
