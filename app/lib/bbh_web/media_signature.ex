defmodule BbhWeb.MediaSignature do
  @moduledoc """
  Signs the variant parameters of a media URL (`w`, `h`, `fx`, `fy`).

  Every variant is generated on first request and kept on disk, so unsigned parameters
  would let anyone mint a new cache file per size/focal combination and fill the disk.
  `BbhWeb.Format.media_url/2` — the only place URLs are built — adds `s`, and
  `BbhWeb.MediaController` generates a variant only when it matches. That bounds the
  cache to the sizes templates actually ask for.

  The MAC covers the parameter strings exactly as they appear in the query, so both
  sides agree without re-parsing. `v` is left out: it only picks the cache header.
  """

  @params ~w(w h fx fy)
  # 64 bits: enough that guessing one is hopeless, short enough for long srcsets.
  @mac_bytes 8

  @doc "The signature for `key` and the given parameters (keyword or string map)."
  def sign(key, params), do: mac(key, params)

  @doc "Whether `params` (the request's string map) carry a valid `s` for `key`."
  def valid?(key, %{"s" => sig} = params) when is_binary(sig),
    do: Plug.Crypto.secure_compare(sig, mac(key, params))

  def valid?(_key, _params), do: false

  defp mac(key, params) do
    payload = Enum.map_join([key | Enum.map(@params, &value(params, &1))], "|", &to_string/1)

    :crypto.mac(:hmac, :sha256, secret(), "bbh-media-variant|" <> payload)
    |> binary_part(0, @mac_bytes)
    |> Base.url_encode64(padding: false)
  end

  defp value(params, name) when is_map(params), do: params[name]
  defp value(params, name), do: params[String.to_existing_atom(name)]

  defp secret, do: BbhWeb.Endpoint.config(:secret_key_base)
end
