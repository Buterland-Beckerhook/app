defmodule BbhWeb.Beta do
  @moduledoc """
  The public beta (beta.buterland-beckerhook.de) runs the same release as the live
  site against its own database. It must never be mistaken for the live site — by
  search engines, AI crawlers or visitors:

    * `BbhWeb.Plugs.NoIndex` stamps `robots_directives/0` on every response,
    * `BbhWeb.RobotsController` disallows every crawler,
    * the root layout adds the same directives as a `<meta name="robots">`, a canonical
      link to the live site and `banner/1` at the top and bottom of every page.

  The flag is set in `runtime.exs`: by `BETA=true`, and by itself on a `beta.` host,
  so a forgotten variable cannot expose the beta.
  """
  use Phoenix.Component

  @live_url "https://buterland-beckerhook.de"

  # `noai`/`noimageai` are not standardized, but several AI crawlers honor them.
  @robots_directives "noindex, nofollow, noarchive, noimageindex, noai, noimageai"

  def enabled?, do: Application.get_env(:bbh, :beta, false)

  def robots_directives, do: @robots_directives

  @doc "The same page on the live site."
  def live_url(path), do: Application.get_env(:bbh, :live_url, @live_url) <> path

  attr :id, :string, required: true
  attr :path, :string, required: true, doc: "request path (with query) of this page"

  def banner(assigns) do
    ~H"""
    <aside
      id={@id}
      role="note"
      class="bg-warning px-4 py-2 text-center text-sm text-warning-content"
    >
      <strong class="font-bold tracking-wide uppercase">Beta-Version</strong>
      – nur zum Testen, Inhalte können veraltet oder unfertig sein.
      <a href={live_url(@path)} class="font-semibold whitespace-nowrap underline">
        Zur echten Seite →
      </a>
    </aside>
    """
  end
end
