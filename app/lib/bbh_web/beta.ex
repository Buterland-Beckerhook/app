defmodule BbhWeb.Beta do
  @moduledoc """
  The public beta (beta.buterland-beckerhook.de) runs the same release as the live
  site against its own database. It must never be mistaken for the live site — by
  search engines, AI crawlers or visitors:

    * `BbhWeb.Plugs.NoIndex` stamps `robots_directives/0` on every response,
    * `BbhWeb.RobotsController` disallows every crawler,
    * the root layout adds the same directives as a `<meta name="robots">`, a canonical
      link to the live site and `banner/1` at the top and bottom of every page. The top
      one is pinned above the sticky site header; its height is `--bb-beta-h`
      (`app.css`), which the header, anchor jumps and the admin sidebar offset by.

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

  attr :pinned, :boolean,
    default: false,
    doc: "stick to the top as one line of height `--bb-beta-h`; the notice shortens on phones"

  def banner(assigns) do
    ~H"""
    <aside
      id={@id}
      role="note"
      class={[
        "bg-warning px-4 text-center text-sm text-warning-content",
        if(@pinned,
          do:
            "sticky top-0 z-50 flex h-(--bb-beta-h) items-center justify-center gap-x-1 overflow-hidden whitespace-nowrap",
          else: "py-2"
        )
      ]}
    >
      <strong class="font-bold tracking-wide uppercase">Beta-Version</strong>
      <span class={@pinned && "hidden md:inline"}>
        – nur zum Testen, Inhalte können veraltet oder unfertig sein.
      </span>
      <a href={live_url(@path)} class="font-semibold whitespace-nowrap underline">
        Zur echten Seite →
      </a>
    </aside>
    """
  end
end
