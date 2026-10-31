defmodule Bbh.Site do
  @moduledoc """
  Where the app is reachable — for the absolute links and origins the domain needs
  outside a request: push and mail links, the WebAuthn relying party.

  Configured per environment (`config :bbh, Bbh.Site, url: …`; prod sets it from
  `PHX_HOST` in `runtime.exs`) and kept equal to the endpoint's URL, so the domain
  never has to ask `BbhWeb.Endpoint`.
  """

  @doc "Absolute base URL without trailing slash, e.g. `https://buterland-beckerhook.de`."
  def url, do: Application.fetch_env!(:bbh, __MODULE__) |> Keyword.fetch!(:url)

  @doc "Host part of `url/0` — the WebAuthn relying-party id."
  def host, do: URI.parse(url()).host
end
