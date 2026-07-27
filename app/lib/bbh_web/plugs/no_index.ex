defmodule BbhWeb.Plugs.NoIndex do
  @moduledoc """
  Stamps `X-Robots-Tag: noindex, nofollow` on every response when the
  `:noindex` flag is enabled (set via `BETA_NOINDEX=true` in `runtime.exs`).

  This is the app-level safety net for the public beta deployment: it keeps the
  site out of search indexes independently of the reverse-proxy `noindex`
  middleware, so protection never rests on a single Traefik label. It is a no-op
  in prod, where the flag is unset.

  Mounted as the first plug in the endpoint (before `Plug.Static`) and using
  `register_before_send/2`, so the header lands on responses produced by every
  later plug too — static assets, router pages and LiveView.
  """
  import Plug.Conn

  @behaviour Plug

  # NOTE: the flag is read at request time, not in `init/1`. Endpoint plugs
  # initialize at compile time, before `runtime.exs` runs, so an `init/1` lookup
  # would bake in the default (false).
  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    if Application.get_env(:bbh, :noindex, false) do
      register_before_send(conn, &put_resp_header(&1, "x-robots-tag", "noindex, nofollow"))
    else
      conn
    end
  end
end
