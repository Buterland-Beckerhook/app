defmodule BbhWeb.MediaController do
  use BbhWeb, :controller

  @max_dimension 4000

  # How long a browser may keep a response.
  #
  # A variant URL names exactly one picture: size, crop and focal point are in the URL,
  # uploads get a fresh key, and the only in-place rewrite of an original — rotation —
  # bumps `revision`, which `BbhWeb.Format.media_url/2` carries as `?v=`. So a variant
  # requested with the *current* revision is cached for a year and never revalidated.
  # Changing the encoder settings (Bbh.Media's @variant_encoding) does not need to bust
  # it: the old file is still a correct rendition of the same picture.
  @immutable "public, max-age=31536000, immutable"
  # Originals (no size requested) can be linked bare from stored rich text, where no
  # `?v=` ever changes; and a variant URL whose `v` is not the current revision is one
  # a rotation has already moved past. Both may change behind the same URL.
  @one_day "public, max-age=86400"
  # The original standing in for a variant that failed to generate: retried soon.
  @fallback "public, max-age=300"

  # sobelow_skip ["Traversal.SendFile", "XSS.ContentType"]
  # resolve_variant/3 rejects any key containing ".." (Bbh.Media.safe_source/1)
  # and returns a content type from a fixed allowlist keyed on the stored
  # extension — never a client-supplied value.
  def show(conn, %{"path" => segments} = params) do
    key = Enum.join(segments, "/")

    case Bbh.Media.resolve_variant(
           key,
           dim(params["w"]),
           dim(params["h"]),
           frac(params["fx"]),
           frac(params["fy"])
         ) do
      {:ok, path, content_type} ->
        serve(conn, path, content_type, cache_control(key, params))

      {:fallback, path, content_type} ->
        serve(conn, path, content_type, @fallback)

      :error ->
        conn |> put_status(:not_found) |> text("Not found")
    end
  end

  # sobelow_skip ["Traversal.SendFile", "XSS.ContentType"]
  # path and content_type come from Bbh.Media.resolve_variant/5 (see show/2).
  defp serve(conn, path, content_type, cache_control) do
    conn
    |> put_resp_content_type(content_type, nil)
    |> put_resp_header("cache-control", cache_control)
    |> maybe_force_download(content_type)
    |> send_file(200, path)
  end

  defp cache_control(key, params) do
    variant? = dim(params["w"]) != nil or dim(params["h"]) != nil

    if variant? and requested_revision(params["v"]) == Bbh.Media.revision(key),
      do: @immutable,
      else: @one_day
  end

  # `media_url/2` leaves `v` off while the revision is 0.
  defp requested_revision(nil), do: 0

  defp requested_revision(value) do
    case Integer.parse(value) do
      {n, ""} when n >= 0 -> n
      _ -> -1
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

  # A focal-point fraction in 0.0..1.0; anything out of range or unparseable is
  # ignored (nil), so the crop simply falls back to center.
  defp frac(nil), do: nil

  defp frac(value) do
    case Float.parse(value) do
      {f, _} when f >= 0.0 and f <= 1.0 -> f
      _ -> nil
    end
  end
end
