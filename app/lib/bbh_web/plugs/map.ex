defmodule BbhWeb.Plugs.Map do
  @moduledoc """
  Serves the self-hosted map under `/karte`, ahead of session and router (see
  `docs/adr/0014-self-hosted-osm-map.md`):

    * `/karte/region.pmtiles` — the archive `Bbh.Map.tiles_path/0` resolves. The
      browser reads it with HTTP Range requests; `Plug.Static` answers those (206,
      416, ETag/304), so this only points it at a directory decided at runtime.
      No archive → passes through to the router's 404.
    * `/karte/fonts/…`, `/karte/sprites/…` — glyphs and sprites from `priv/map`.
      A glyph range we don't ship gets an empty glyph set instead of a 404, so a
      stray character can't flood the 404 log; the label just goes without it.

  Everything else passes through untouched.
  """
  import Plug.Conn

  @tiles "region.pmtiles"
  @glyph_range ~r/\A\d+-\d+\.pbf\z/

  def init(opts), do: opts

  def call(%Plug.Conn{path_info: ["karte", @tiles]} = conn, _opts) do
    case Bbh.Map.tiles_path() do
      nil ->
        conn

      path ->
        name = Path.basename(path)

        conn
        |> Map.put(:path_info, [name])
        |> Plug.Static.call(tiles_static(Path.dirname(path), name))
        |> restore_path(conn)
    end
  end

  def call(%Plug.Conn{path_info: ["karte", dir | _]} = conn, _opts)
      when dir in ["fonts", "sprites"] do
    conn
    |> Plug.Static.call(assets_static())
    |> empty_glyphs()
  end

  def call(conn, _opts), do: conn

  # Plug.Static only saw the archive's own file name; if it passed (method not
  # served), hand the original path on.
  defp restore_path(%Plug.Conn{halted: true} = served, _original), do: served
  defp restore_path(_served, original), do: original

  defp empty_glyphs(%Plug.Conn{halted: true} = conn), do: conn

  defp empty_glyphs(
         %Plug.Conn{method: method, path_info: ["karte", "fonts", _stack, range]} = conn
       )
       when method in ["GET", "HEAD"] do
    if Regex.match?(@glyph_range, range) do
      conn
      |> put_resp_content_type("application/x-protobuf", nil)
      |> put_resp_header("cache-control", "public, max-age=86400")
      |> send_resp(200, "")
      |> halt()
    else
      conn
    end
  end

  defp empty_glyphs(conn), do: conn

  # The archive changes monthly at most and the tiles URL carries its version, so a
  # day of caching is safe; `no-transform` keeps a compressing proxy away from the
  # byte ranges (the tiles inside are gzipped already).
  defp tiles_static(dir, name) do
    Plug.Static.init(
      at: "/",
      from: dir,
      only: [name],
      cache_control_for_etags: "public, max-age=86400, no-transform",
      content_types: %{name => "application/vnd.pmtiles"}
    )
  end

  defp assets_static do
    Plug.Static.init(
      at: "/karte",
      from: {:bbh, "priv/map"},
      cache_control_for_etags: "public, max-age=86400"
    )
  end
end
