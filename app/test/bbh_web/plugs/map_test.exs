defmodule BbhWeb.Plugs.MapTest do
  # Not async: the map directory is application config.
  use BbhWeb.ConnCase, async: false

  import Bbh.MapFixtures

  setup do
    with_map_dir()
    :ok
  end

  describe "/karte/region.pmtiles" do
    setup do
      %{bytes: File.read!(write_pmtiles(Bbh.Map.target_path()))}
    end

    test "answers a byte range with 206 and exactly those bytes", %{conn: conn, bytes: bytes} do
      conn = conn |> put_req_header("range", "bytes=0-126") |> get("/karte/region.pmtiles")

      assert conn.status == 206
      assert conn.resp_body == binary_part(bytes, 0, 127)
      assert get_resp_header(conn, "content-range") == ["bytes 0-126/#{byte_size(bytes)}"]
      assert get_resp_header(conn, "accept-ranges") == ["bytes"]
      assert get_resp_header(conn, "content-type") == ["application/vnd.pmtiles"]
      assert [etag] = get_resp_header(conn, "etag")
      assert get_resp_header(conn, "cache-control") == ["public, max-age=86400, no-transform"]

      conn =
        build_conn()
        |> put_req_header("if-none-match", etag)
        |> put_req_header("range", "bytes=0-126")
        |> get("/karte/region.pmtiles")

      assert conn.status == 304
    end

    test "serves open-ended and suffix ranges", %{conn: conn, bytes: bytes} do
      size = byte_size(bytes)

      conn =
        conn |> put_req_header("range", "bytes=#{size - 10}-") |> get("/karte/region.pmtiles")

      assert conn.status == 206
      assert conn.resp_body == binary_part(bytes, size - 10, 10)

      conn = build_conn() |> put_req_header("range", "bytes=-5") |> get("/karte/region.pmtiles")
      assert conn.status == 206
      assert conn.resp_body == binary_part(bytes, size - 5, 5)
    end

    test "answers a range past the end with 416", %{conn: conn, bytes: bytes} do
      conn =
        conn
        |> put_req_header("range", "bytes=#{byte_size(bytes)}-")
        |> get("/karte/region.pmtiles")

      assert conn.status == 416
    end

    test "serves the whole file without a range", %{conn: conn, bytes: bytes} do
      conn = get(conn, "/karte/region.pmtiles")
      assert conn.status == 200
      assert conn.resp_body == bytes
    end
  end

  test "without an archive the tiles URL is a plain 404", %{conn: conn} do
    assert conn |> get("/karte/region.pmtiles") |> response(404)
  end

  describe "glyphs and sprites" do
    test "are served from priv/map", %{conn: conn} do
      conn = get(conn, "/karte/fonts/Noto%20Sans%20Regular/0-255.pbf")
      assert conn.status == 200
      assert byte_size(conn.resp_body) > 1000

      assert build_conn() |> get("/karte/sprites/v4/dark.json") |> json_response(200)
    end

    test "a glyph range we don't ship is an empty glyph set, not a 404", %{conn: conn} do
      conn = get(conn, "/karte/fonts/Noto%20Sans%20Regular/19968-20223.pbf")
      assert conn.status == 200
      assert conn.resp_body == ""
    end

    test "anything else under /karte/fonts is still a 404", %{conn: conn} do
      assert conn |> get("/karte/fonts/Noto%20Sans%20Regular/secret.txt") |> response(404)
    end
  end
end
