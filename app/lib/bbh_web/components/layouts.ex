defmodule BbhWeb.Layouts do
  @moduledoc """
  This module holds layouts and related functionality
  used by your application.
  """
  use BbhWeb, :html

  # Embed all files in layouts/* within this module.
  # The default root.html.heex file contains the HTML
  # skeleton of your application, namely HTML headers
  # and other static content.
  embed_templates "layouts/*"

  @doc """
  Renders your app layout.

  This function is typically invoked from every template,
  and it often contains your application menu, sidebar,
  or similar.

  ## Examples

      <Layouts.app flash={@flash}>
        <h1>Content</h1>
      </Layouts.app>

  """
  @nav [
    %{href: "/aktuell", label: "Aktuelles"},
    %{href: "/termine", label: "Termine"},
    %{
      href: "/thron",
      label: "Thron",
      children: [
        %{href: "/thron", label: "Throne seit 1909"},
        %{href: "/aktuell/2009/kaiserthron-2009", label: "Kaiserthron 2009"},
        %{href: "/aktuell/1984/kaiserthron-1984", label: "Kaiserthron 1984"}
      ]
    },
    %{
      href: "/verein",
      label: "Verein",
      children: [
        %{href: "/verein", label: "Über uns"},
        %{href: "/verein/vorstand", label: "Vorstand"},
        %{href: "/verein/offiziere", label: "Offiziere"},
        %{href: "/verein/jungschuetzen", label: "Jungschützen"},
        %{href: "/verein/kinderfest", label: "Kinderfest"},
        %{href: "/verein/mitglied-werden", label: "Mitglied werden"}
      ]
    },
    %{href: "/kontakt", label: "Kontakt"}
  ]

  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :current_path, :string, default: "/", doc: "request path, for active nav highlighting"

  attr :current_scope, :map,
    default: nil,
    doc: "the current [scope](https://phoenix.hexdocs.pm/scopes.html)"

  slot :inner_block, required: true

  def app(assigns) do
    assigns = assign(assigns, :nav, @nav)

    ~H"""
    <div class="flex min-h-screen flex-col bg-base-100 text-base-content">
      <header class="sticky top-0 z-40 border-b border-base-300 bg-(--bb-header-bg) backdrop-blur-md backdrop-saturate-150">
        <nav class="mx-auto flex max-w-6xl items-center justify-between gap-6 px-4 py-3">
          <a href="/" class="flex items-center gap-3.5">
            <img
              src={~p"/images/logo.svg"}
              alt=""
              width="52"
              height="52"
              class="h-13 w-13"
            />
            <div class="leading-tight">
              <span class="block text-xs font-semibold tracking-[0.14em] text-muted uppercase">
                Schützenverein
              </span>
              <span class="font-logo block text-lg font-bold text-primary md:text-[23px]">
                Buterland-Beckerhook e.V.
              </span>
            </div>
          </a>

          <%!-- Desktop nav --%>
          <div class="hidden items-center gap-6 md:flex">
            <%= for link <- @nav do %>
              <%= if link[:children] do %>
                <div class="group relative">
                  <a
                    href={link.href}
                    class={[
                      "flex items-center gap-1 text-[15px] transition-colors",
                      nav_active?(@current_path, link) && "font-semibold text-primary",
                      !nav_active?(@current_path, link) &&
                        "font-medium text-(--bb-nav-text) hover:text-primary"
                    ]}
                  >
                    {link.label}
                    <.icon name="hero-chevron-down-mini" class="size-4" />
                  </a>
                  <div class="invisible absolute top-full left-0 z-50 min-w-48 pt-2 opacity-0 transition-all group-hover:visible group-hover:opacity-100">
                    <div class="rounded-xl border border-base-300 bg-card py-1 shadow-lg">
                      <a
                        :for={child <- link.children}
                        href={child.href}
                        class={[
                          "block px-4 py-2 text-sm transition-colors",
                          child_active?(@current_path, child.href, link.href) &&
                            "bg-base-200 font-medium text-primary",
                          !child_active?(@current_path, child.href, link.href) &&
                            "text-muted hover:bg-base-200 hover:text-primary"
                        ]}
                      >
                        {child.label}
                      </a>
                    </div>
                  </div>
                </div>
              <% else %>
                <a
                  href={link.href}
                  class={[
                    "text-[15px] transition-colors",
                    nav_active?(@current_path, link) && "font-semibold text-primary",
                    !nav_active?(@current_path, link) &&
                      "font-medium text-(--bb-nav-text) hover:text-primary"
                  ]}
                >
                  {link.label}
                </a>
              <% end %>
            <% end %>
            <a
              href={~p"/verein/mitglied-werden"}
              class="rounded-full bg-accent px-4.5 py-2 text-[15px] font-semibold whitespace-nowrap text-accent-content transition-opacity hover:opacity-90"
            >
              Mitglied werden
            </a>
          </div>

          <%!-- Mobile menu (daisyUI dropdown, no custom JS) --%>
          <div class="dropdown dropdown-end md:hidden">
            <button
              tabindex="0"
              class="flex items-center text-(--bb-nav-text)"
              aria-label="Menü öffnen"
            >
              <.icon name="hero-bars-3" class="size-6" />
            </button>
            <ul
              tabindex="0"
              class="dropdown-content menu z-50 mt-2 w-64 rounded-box border border-base-300 bg-card p-2 shadow-lg"
            >
              <%= for link <- @nav do %>
                <li>
                  <a href={link.href} class="font-medium">{link.label}</a>
                  <ul :if={link[:children]}>
                    <li :for={child <- link.children}>
                      <a href={child.href}>{child.label}</a>
                    </li>
                  </ul>
                </li>
              <% end %>
              <li class="mt-2">
                <a
                  href={~p"/verein/mitglied-werden"}
                  class="rounded-full bg-accent text-center font-semibold text-accent-content"
                >
                  Mitglied werden
                </a>
              </li>
            </ul>
          </div>
        </nav>
      </header>

      <main class="mx-auto w-full max-w-6xl flex-1 px-4 py-8">
        {render_slot(@inner_block)}
      </main>

      <%!-- Deliberately the same dark green in both themes (design handoff). --%>
      <footer class="mt-16 bg-[#0d2617] text-[#cfe0d4]">
        <div class="mx-auto grid max-w-6xl gap-10 px-4 py-12 md:grid-cols-[1.4fr_1fr_1fr]">
          <div>
            <div class="flex items-center gap-3">
              <img src={~p"/images/logo.svg"} alt="" width="44" height="44" class="h-11 w-11" />
              <span class="font-logo text-[19px] font-bold text-white">
                Buterland-Beckerhook e.V.
              </span>
            </div>
            <p class="mt-4 max-w-xs text-sm leading-relaxed text-[#9fb6a8]">
              Schützenverein Buterland-Beckerhook e.V. von 1909 aus Gronau (Westf.).
              Tradition, Kameradschaft und Schützenfest.
            </p>
          </div>
          <div>
            <h2 class="mb-3.5 text-[13px] tracking-[0.1em] text-white uppercase">Seiten</h2>
            <div class="flex flex-col gap-2.5 text-[15px]">
              <a href={~p"/aktuell"} class="text-[#cfe0d4] hover:text-white">Aktuelles</a>
              <a href={~p"/termine"} class="text-[#cfe0d4] hover:text-white">Termine</a>
              <a href={~p"/thron"} class="text-[#cfe0d4] hover:text-white">Thron</a>
              <a href={~p"/verein"} class="text-[#cfe0d4] hover:text-white">Verein</a>
            </div>
          </div>
          <div>
            <h2 class="mb-3.5 text-[13px] tracking-[0.1em] text-white uppercase">Kontakt</h2>
            <div class="flex flex-col items-start gap-2.5 text-[15px]">
              <a href={~p"/kontakt"} class="text-[#cfe0d4] hover:text-white">Kontaktformular</a>
              <a href={~p"/impressum"} class="text-[#cfe0d4] hover:text-white">Impressum</a>
              <a href={~p"/datenschutz"} class="text-[#cfe0d4] hover:text-white">Datenschutz</a>
              <button
                id="push-optin"
                type="button"
                class="cursor-pointer text-left text-[#cfe0d4] hover:text-white"
              >
                Benachrichtigungen aktivieren
              </button>
            </div>
          </div>
        </div>
        <div class="border-t border-white/10">
          <div class="mx-auto flex max-w-6xl flex-wrap items-center justify-between gap-4 px-4 py-4">
            <p class="text-[13px] text-[#8ba597]">
              &copy; {Date.utc_today().year} Schützenverein Buterland-Beckerhook e.V.
            </p>
            <.theme_toggle />
          </div>
        </div>
      </footer>
    </div>

    <.flash_group flash={@flash} />
    """
  end

  @child_hrefs Enum.flat_map(@nav, fn l -> Enum.map(l[:children] || [], & &1.href) end)

  # Top-level link is active on exact match, or as a section prefix for /aktuell and
  # /termine — but not when the path belongs to a dropdown child (e.g. a Thron article).
  defp nav_active?(path, %{children: children}),
    do: Enum.any?(children, fn c -> child_active?(path, c.href, nil) end)

  defp nav_active?(path, %{href: href}) when href in ["/aktuell", "/termine"] do
    section = path == href or String.starts_with?(path, href <> "/")
    section and not Enum.any?(@child_hrefs, &(path == &1 or String.starts_with?(path, &1 <> "/")))
  end

  defp nav_active?(path, %{href: href}), do: path == href

  # A "Über uns"-style child whose href equals its parent matches exactly only.
  defp child_active?(path, href, parent_href) when href == parent_href, do: path == href

  defp child_active?(path, href, _parent),
    do: path == href or String.starts_with?(path, href <> "/")

  # Sections are added here as their CRUD is built.
  @admin_nav [
    {:dashboard, "/admin", "Übersicht"},
    {:articles, "/admin/artikel", "Artikel"},
    {:events, "/admin/termine", "Termine"},
    {:locations, "/admin/orte", "Orte"},
    {:people, "/admin/personen", "Personen"},
    {:pages, "/admin/seiten", "Seiten"},
    {:media, "/admin/medien", "Medien"}
  ]

  @doc "Admin area layout: mobile-first drawer nav + content."
  attr :flash, :map, required: true
  attr :current_scope, :map, required: true
  attr :active, :atom, default: nil, doc: "the active nav section"
  slot :inner_block, required: true

  def admin(assigns) do
    assigns = assign(assigns, :nav, visible_nav(assigns.current_scope))

    ~H"""
    <div class="drawer lg:drawer-open">
      <input id="admin-drawer" type="checkbox" class="drawer-toggle" />
      <div class="drawer-content flex min-h-screen flex-col bg-base-100">
        <header class="navbar border-b border-base-300 bg-base-100 lg:hidden">
          <label for="admin-drawer" class="btn btn-square btn-ghost" aria-label="Menü">
            <.icon name="hero-bars-3" class="size-6" />
          </label>
          <span class="font-logo px-2 text-lg text-primary">Verwaltung</span>
        </header>
        <main class="flex-1 p-4 sm:p-6">
          <.flash_group flash={@flash} />
          {render_slot(@inner_block)}
        </main>
      </div>

      <div class="drawer-side z-40">
        <label for="admin-drawer" class="drawer-overlay" aria-label="Menü schließen"></label>
        <aside class="flex min-h-full w-64 flex-col bg-base-200">
          <a href={~p"/admin"} class="font-logo block px-4 py-4 text-xl text-primary">
            Buterland-Beckerhook
          </a>
          <ul class="menu flex-1 px-2">
            <li :for={{key, href, label} <- @nav}>
              <.link navigate={href} class={@active == key && "menu-active font-semibold"}>
                {label}
              </.link>
            </li>
            <li :if={admin_user?(@current_scope)}>
              <.link
                navigate={~p"/admin/benutzer"}
                class={@active == :users && "menu-active font-semibold"}
              >
                Benutzer
              </.link>
            </li>
          </ul>
          <div class="border-t border-base-300 p-4 text-sm">
            <p class="truncate text-base-content/70">{@current_scope.user.email}</p>
            <div class="mt-2 flex flex-wrap items-center gap-x-3 gap-y-1">
              <a href={~p"/"} class="link link-hover">Zur Website</a>
              <.link navigate={~p"/admin/einstellungen"} class="link link-hover">Einstellungen</.link>
              <.link href={~p"/users/log-out"} method="delete" class="link link-hover">Abmelden</.link>
            </div>
          </div>
        </aside>
      </div>
    </div>
    """
  end

  defp admin_user?(%{user: user}), do: Bbh.Accounts.User.admin?(user)
  defp admin_user?(_), do: false

  # Only show sections the current user may actually open.
  defp visible_nav(%{user: user}),
    do:
      Enum.filter(@admin_nav, fn {key, _href, _label} ->
        BbhWeb.Authz.can_access_section?(user, key)
      end)

  defp visible_nav(_), do: []

  attr :nonce, :string, default: nil

  @doc "Cookieless Matomo analytics snippet (only rendered when configured)."
  def matomo(assigns) do
    cfg = Application.get_env(:bbh, :matomo, [])
    assigns = assign(assigns, :script, matomo_script(cfg[:url], cfg[:site_id], assigns[:nonce]))

    ~H"{@script}"
  end

  defp matomo_script(url, site_id, nonce)
       when is_binary(url) and (is_binary(site_id) or is_integer(site_id)) do
    u = if String.ends_with?(url, "/"), do: url, else: url <> "/"

    js =
      "var _paq=window._paq=window._paq||[];_paq.push(['disableCookies']);" <>
        "_paq.push(['trackPageView']);_paq.push(['enableLinkTracking']);" <>
        "(function(){var u=\"#{u}\";_paq.push(['setTrackerUrl',u+'matomo.php']);" <>
        "_paq.push(['setSiteId','#{site_id}']);var d=document,g=d.createElement('script')," <>
        "s=d.getElementsByTagName('script')[0];g.async=true;g.src=u+'matomo.js';" <>
        "s.parentNode.insertBefore(g,s);})();"

    Phoenix.HTML.raw(~s(<script#{nonce_attr(nonce)}>#{js}</script>))
  end

  defp matomo_script(_url, _site_id, _nonce), do: nil

  defp nonce_attr(nonce) when is_binary(nonce) and nonce != "", do: ~s( nonce="#{nonce}")
  defp nonce_attr(_), do: ""

  @doc """
  Shows the flash group with standard titles and content.

  ## Examples

      <.flash_group flash={@flash} />
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :id, :string, default: "flash-group", doc: "the optional id of flash container"

  def flash_group(assigns) do
    ~H"""
    <div id={@id} aria-live="polite">
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:error} flash={@flash} />

      <.flash
        id="client-error"
        kind={:error}
        title={gettext("We can't find the internet")}
        phx-disconnected={
          show(".phx-client-error #client-error")
          |> JS.remove_attribute("hidden", to: ".phx-client-error #client-error")
        }
        phx-connected={hide("#client-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>

      <.flash
        id="server-error"
        kind={:error}
        title={gettext("Something went wrong!")}
        phx-disconnected={
          show(".phx-server-error #server-error")
          |> JS.remove_attribute("hidden", to: ".phx-server-error #server-error")
        }
        phx-connected={hide("#server-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>
    </div>
    """
  end

  @doc """
  Provides dark vs light theme toggle based on themes defined in app.css.
  Styled for the dark footer it lives in.

  See <head> in root.html.heex which applies the theme before page load.
  """
  def theme_toggle(assigns) do
    ~H"""
    <div class="relative flex flex-row items-center rounded-full border border-white/20 bg-white/10">
      <div class="absolute h-full w-1/3 rounded-full bg-white [[data-theme=dark]_&]:bg-[#1c7d47] left-0 [[data-theme=light]_&]:left-1/3 [[data-theme=dark]_&]:left-2/3 [[data-theme-source=system]_&]:!left-0 transition-[left]" />

      <button
        class="relative flex w-1/3 cursor-pointer justify-center p-2 text-[#cfe0d4] [[data-theme-source=system]_&]:text-[#0f4d2c] [[data-theme-source=system][data-theme=dark]_&]:text-white"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="system"
        aria-label="Systemeinstellung"
        title="System"
      >
        <.icon name="hero-computer-desktop-micro" class="size-4" />
      </button>

      <button
        class="relative flex w-1/3 cursor-pointer justify-center p-2 text-[#cfe0d4] [[data-theme=light][data-theme-source=user]_&]:text-[#0f4d2c]"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="light"
        aria-label="Helles Design"
        title="Hell"
      >
        <.icon name="hero-sun-micro" class="size-4" />
      </button>

      <button
        class="relative flex w-1/3 cursor-pointer justify-center p-2 text-[#cfe0d4] [[data-theme=dark][data-theme-source=user]_&]:text-white"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="dark"
        aria-label="Dunkles Design"
        title="Dunkel"
      >
        <.icon name="hero-moon-micro" class="size-4" />
      </button>
    </div>
    """
  end
end
