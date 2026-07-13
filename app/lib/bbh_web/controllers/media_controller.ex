defmodule BbhWeb.MediaController do
  use BbhWeb, :controller

  @max_dimension 4000

  def show(conn, %{"path" => segments} = params) do
    key = Enum.join(segments, "/")

    case Bbh.Media.resolve_variant(key, dim(params["w"]), dim(params["h"])) do
      {:ok, path, content_type} ->
        conn
        |> put_resp_content_type(content_type, nil)
        |> put_resp_header("cache-control", "public, max-age=604800")
        |> send_file(200, path)

      :error ->
        conn |> put_status(:not_found) |> text("Not found")
    end
  end

  defp dim(nil), do: nil

  defp dim(value) do
    case Integer.parse(value) do
      {n, _} when n > 0 and n <= @max_dimension -> n
      _ -> nil
    end
  end
end
