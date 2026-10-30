defmodule BbhWeb.MediaUrlHelpers do
  @moduledoc "Test helpers for the signed variant URLs `BbhWeb.Format.media_url/2` builds."

  @doc "Drops the `s` signature, so assertions can name the variant parameters only."
  def unsigned(html) when is_binary(html),
    do: String.replace(html, ~r/(&amp;|&)s=[A-Za-z0-9_-]+/, "")

  @doc "A variant path for `key` with `params` (string map) and a valid signature."
  def signed_path(key, params) do
    sig = BbhWeb.MediaSignature.sign(key, params)
    "/media/#{key}?" <> URI.encode_query(Map.put(params, "s", sig))
  end
end
