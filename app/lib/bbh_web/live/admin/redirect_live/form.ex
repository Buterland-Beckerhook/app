defmodule BbhWeb.Admin.RedirectLive.Form do
  @moduledoc "Create / edit / delete one redirect. `?von=` prefills the source (404 log)."
  use BbhWeb, :live_view

  alias Bbh.Redirects
  alias Bbh.Redirects.Redirect

  @impl true
  def mount(params, _session, socket) do
    {:ok, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :new, params) do
    redirect = %Redirect{source_path: params["von"]}

    socket
    |> assign(page_title: "Neue Weiterleitung", redirect: redirect)
    |> assign_form(Redirects.change_redirect(redirect))
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    redirect = Redirects.get_redirect!(id)

    socket
    |> assign(page_title: "Weiterleitung bearbeiten", redirect: redirect)
    |> assign_form(Redirects.change_redirect(redirect))
  end

  @impl true
  def handle_event("validate", %{"redirect" => params}, socket) do
    changeset =
      socket.assigns.redirect |> Redirects.change_redirect(params) |> Map.put(:action, :validate)

    {:noreply, assign_form(socket, changeset)}
  end

  def handle_event("save", %{"redirect" => params}, socket) do
    save(socket, socket.assigns.live_action, params)
  end

  def handle_event("delete", %{"confirm" => confirm}, socket) do
    redirect = socket.assigns.redirect

    if confirm == redirect.source_path do
      {:ok, _} = Redirects.delete_redirect(redirect)

      {:noreply,
       socket
       |> put_flash(:info, "Weiterleitung gelöscht.")
       |> push_navigate(to: ~p"/admin/weiterleitungen")}
    else
      {:noreply, put_flash(socket, :error, "Der eingegebene Wert stimmt nicht überein.")}
    end
  end

  defp save(socket, :new, params) do
    case Redirects.create_redirect(params) do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:info, "Weiterleitung erstellt.")
         |> push_navigate(to: ~p"/admin/weiterleitungen")}

      {:error, changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  defp save(socket, :edit, params) do
    case Redirects.update_redirect(socket.assigns.redirect, params) do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:info, "Weiterleitung gespeichert.")
         |> push_navigate(to: ~p"/admin/weiterleitungen")}

      {:error, changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  defp assign_form(socket, changeset),
    do: assign(socket, :form, to_form(changeset, as: "redirect"))

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.admin flash={@flash} current_scope={@current_scope} active={:redirects}>
      <.header>{@page_title}</.header>

      <.form
        for={@form}
        id="redirect-form"
        phx-change="validate"
        phx-submit="save"
        class="mt-6 space-y-4"
      >
        <.input
          field={@form[:source_path]}
          label="Von (alte Adresse)"
          placeholder="/verein/vorstand/kontakt"
          required
        />
        <p class="-mt-2 text-xs text-base-content/60">
          Groß-/Kleinschreibung und ein „/“ am Ende spielen keine Rolle. Mit „/*“ am Ende
          gilt die Regel für alles darunter, z. B. <span class="font-mono">/tags/*</span>.
        </p>
        <.input
          field={@form[:target]}
          label="Nach"
          placeholder="/verein/vorstand oder https://…"
          required
        />
        <.input
          field={@form[:permanent]}
          type="checkbox"
          label="Dauerhaft (301) – für Suchmaschinen; aus = vorübergehend (302)"
        />
        <.input field={@form[:note]} label="Notiz (optional)" />

        <div class="flex gap-2">
          <.button variant="primary" phx-disable-with="Speichern…">Speichern</.button>
          <.button navigate={~p"/admin/weiterleitungen"}>Abbrechen</.button>
        </div>
      </.form>

      <.danger_zone :if={@live_action == :edit} confirm_value={@redirect.source_path}>
        Die Weiterleitung von „{@redirect.source_path}" wird dauerhaft gelöscht.
      </.danger_zone>
    </Layouts.admin>
    """
  end
end
