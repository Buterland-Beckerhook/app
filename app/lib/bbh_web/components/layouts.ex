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
    <div class="flex min-h-screen flex-col bg-white text-gray-900 dark:bg-zinc-900 dark:text-gray-200">
      <header class="border-b border-gray-200 bg-white dark:border-zinc-700 dark:bg-zinc-900">
        <nav class="mx-auto flex max-w-6xl items-center justify-between px-4 py-2">
          <a href="/" class="flex items-center gap-3">
            <img src={~p"/images/logo.svg"} alt="" width="48" height="48" class="h-12 w-12 md:h-20 md:w-20" />
            <div class="font-logo leading-tight">
              <span class="block text-sm text-gray-600 md:text-xl dark:text-gray-400">Schützenverein</span>
              <span class="block text-xl text-primary md:text-3xl">Buterland-Beckerhook e.V.</span>
            </div>
          </a>

    <!-- Desktop nav -->
          <div class="hidden items-center gap-6 md:flex">
            <%= for link <- @nav do %>
              <%= if link[:children] do %>
                <div class="group relative">
                  <a
                    href={link.href}
                    class={[
                      "flex items-center gap-1 transition-colors",
                      nav_active?(@current_path, link) && "font-semibold text-primary",
                      !nav_active?(@current_path, link) &&
                        "text-gray-600 hover:text-primary dark:text-gray-300 dark:hover:text-primary"
                    ]}
                  >
                    {link.label}
                    <.icon name="hero-chevron-down-mini" class="size-4" />
                  </a>
                  <div class="invisible absolute top-full left-0 z-50 min-w-48 pt-2 opacity-0 transition-all group-hover:visible group-hover:opacity-100">
                    <div class="rounded-lg border border-gray-200 bg-white py-1 shadow-lg dark:border-zinc-700 dark:bg-zinc-800">
                      <a
                        :for={child <- link.children}
                        href={child.href}
                        class={[
                          "block px-4 py-2 text-sm transition-colors",
                          child_active?(@current_path, child.href, link.href) &&
                            "bg-gray-50 font-medium text-primary dark:bg-zinc-700",
                          !child_active?(@current_path, child.href, link.href) &&
                            "text-gray-600 hover:bg-gray-50 hover:text-primary dark:text-gray-300 dark:hover:bg-zinc-700 dark:hover:text-primary"
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
                    "transition-colors",
                    nav_active?(@current_path, link) && "font-semibold text-primary",
                    !nav_active?(@current_path, link) &&
                      "text-gray-600 hover:text-primary dark:text-gray-300 dark:hover:text-primary"
                  ]}
                >
                  {link.label}
                </a>
              <% end %>
            <% end %>
            <.theme_toggle />
          </div>

    <!-- Mobile menu (daisyUI dropdown, no custom JS) -->
          <div class="dropdown dropdown-end md:hidden">
            <button tabindex="0" class="flex items-center text-gray-600 dark:text-gray-300" aria-label="Menü öffnen">
              <.icon name="hero-bars-3" class="size-6" />
            </button>
            <ul tabindex="0" class="dropdown-content menu z-50 mt-2 w-64 rounded-box border border-gray-200 bg-white p-2 shadow-lg dark:border-zinc-700 dark:bg-zinc-800">
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
              <li class="mt-2 border-t border-gray-200 pt-2 dark:border-zinc-700">
                <.theme_toggle />
              </li>
            </ul>
          </div>
        </nav>
      </header>

      <main class="mx-auto w-full max-w-6xl flex-1 px-4 py-8">
        {render_slot(@inner_block)}
      </main>

      <footer class="border-t border-gray-200 bg-gray-50 text-sm text-gray-500 dark:border-zinc-700 dark:bg-zinc-800 dark:text-gray-400">
        <div class="mx-auto flex max-w-6xl flex-col items-center gap-2 px-4 py-6 md:flex-row md:justify-between">
          <p>&copy; {Date.utc_today().year} Schützenverein Buterland-Beckerhook e.V.</p>
          <div class="flex flex-wrap items-center gap-4">
            <button id="push-optin" type="button" class="hover:text-primary">
              Benachrichtigungen aktivieren
            </button>
            <a href="/impressum" class="hover:text-primary">Impressum</a>
            <a href="/datenschutz" class="hover:text-primary">Datenschutz</a>
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
  defp child_active?(path, href, _parent), do: path == href or String.starts_with?(path, href <> "/")

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
    assigns = assign(assigns, :nav, @admin_nav)

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
              <.link navigate={~p"/admin/benutzer"} class={@active == :users && "menu-active font-semibold"}>
                Benutzer
              </.link>
            </li>
          </ul>
          <div class="border-t border-base-300 p-4 text-sm">
            <p class="truncate text-base-content/70">{@current_scope.user.email}</p>
            <div class="mt-2 flex flex-wrap items-center gap-x-3 gap-y-1">
              <a href={~p"/"} class="link link-hover">Zur Website</a>
              <.link navigate={~p"/users/2fa"} class="link link-hover">2FA</.link>
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

  @doc "Cookieless Matomo analytics snippet (only rendered when configured)."
  def matomo(assigns) do
    cfg = Application.get_env(:bbh, :matomo, [])
    assigns = assign(assigns, :script, matomo_script(cfg[:url], cfg[:site_id]))

    ~H"{@script}"
  end

  defp matomo_script(url, site_id)
       when is_binary(url) and (is_binary(site_id) or is_integer(site_id)) do
    u = if String.ends_with?(url, "/"), do: url, else: url <> "/"

    js =
      "var _paq=window._paq=window._paq||[];_paq.push(['disableCookies']);" <>
        "_paq.push(['trackPageView']);_paq.push(['enableLinkTracking']);" <>
        "(function(){var u=\"#{u}\";_paq.push(['setTrackerUrl',u+'matomo.php']);" <>
        "_paq.push(['setSiteId','#{site_id}']);var d=document,g=d.createElement('script')," <>
        "s=d.getElementsByTagName('script')[0];g.async=true;g.src=u+'matomo.js';" <>
        "s.parentNode.insertBefore(g,s);})();"

    Phoenix.HTML.raw("<script>#{js}</script>")
  end

  defp matomo_script(_url, _site_id), do: nil

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

  See <head> in root.html.heex which applies the theme before page load.
  """
  def theme_toggle(assigns) do
    ~H"""
    <div class="card relative flex flex-row items-center border-2 border-base-300 bg-base-300 rounded-full">
      <div class="absolute w-1/3 h-full rounded-full border-1 border-base-200 bg-base-100 brightness-200 left-0 [[data-theme=light]_&]:left-1/3 [[data-theme=dark]_&]:left-2/3 [[data-theme-source=system]_&]:!left-0 transition-[left]" />

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="system"
      >
        <.icon name="hero-computer-desktop-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="light"
      >
        <.icon name="hero-sun-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="dark"
      >
        <.icon name="hero-moon-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>
    </div>
    """
  end
end
