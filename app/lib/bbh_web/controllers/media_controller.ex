defmodule BbhWeb.MediaController do
  use BbhWeb, :controller

  @max_dimension 4000

  # sobelow_skip ["Traversal.SendFile", "XSS.ContentType"]
  # resolve_variant/3 rejects any key containing ".." (Bbh.Media.safe_source/1)
  # and returns a content type from a fixed allowlist keyed on the stored
  # extension — never a client-supplied value.
  def show(conn, %{"path" => segments} = params) do
    key = Enum.join(segments, "/")

    case Bbh.Media.resolve_variant(key, dim(params["w"]), dim(params["h"])) do
      {:ok, path, content_type} ->
        conn
        |> put_resp_content_type(content_type, nil)
        |> put_resp_header("cache-control", "public, max-age=604800")
        |> maybe_force_download(content_type)
        |> send_file(200, path)

      :error ->
        conn |> put_status(:not_found) |> text("Not found")
    end
  end

  # SVG can carry scripts; never let the browser render it inline in our origin.
  defp maybe_force_download(conn, "image/svg+xml"),
    do: put_resp_header(conn, "content-disposition", "attachment")

  defp maybe_force_download(conn, _content_type), do: conn

  defp dim(nil), do: nil

  defp dim(value) do
    case Integer.parse(value) do
      {n, _} when n > 0 and n <= @max_dimension -> n
      _ -> nil
    end
  end
end
