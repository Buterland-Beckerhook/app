defmodule BbhWeb.Redirector do
  @moduledoc """
  The site's single 404 path. Every "not found" — no route matched
  (`BbhWeb.NotFoundController`), or a controller found no record
  (`BbhWeb.ControllerHelpers.not_found/1`) — ends here, which:

    1. redirects when `Bbh.Redirects.resolve/1` knows a target (GET/HEAD only), else
    2. records the path in the 404 log (`Bbh.Redirects.record_not_found/2`) and
    3. renders the 404 page (`BbhWeb.NotFoundHTML`, in the site layout).

  Because redirects are only looked up here, a rule can never shadow a live page.

  Config (`config :bbh, __MODULE__, ...`): `async: false` writes the 404 log inline
  instead of via `Bbh.TaskSupervisor` (tests, so the write stays in the SQL sandbox).
  """
  import Plug.Conn
  import Phoenix.Controller

  alias Bbh.Redirects

  @doc "Redirect if a rule or legacy mapping applies; otherwise log and render the 404."
  def not_found(conn) do
    case redirect_target(conn) do
      {target, status} ->
        conn
        |> put_status(status)
        |> do_redirect(target)
        |> halt()

      nil ->
        maybe_log(conn)
        render_404(conn)
    end
  end

  defp redirect_target(%Plug.Conn{method: method} = conn) when method in ["GET", "HEAD"] do
    case Redirects.resolve(conn.request_path) do
      {:rule, rule} ->
        Redirects.track_hit(rule.id)
        {rule.target, if(rule.permanent, do: :moved_permanently, else: :found)}

      {:legacy, target} ->
        {target, :moved_permanently}

      nil ->
        nil
    end
  end

  defp redirect_target(_conn), do: nil

  # Targets were validated on write (site path or http(s) URL).
  defp do_redirect(conn, "/" <> _ = path), do: redirect(conn, to: path)
  defp do_redirect(conn, url), do: redirect(conn, external: url)

  @links [
    {"/", "Startseite", "Neuigkeiten, nächste Termine und der aktuelle Thron"},
    {"/aktuell", "Aktuelles", "Berichte und Neuigkeiten aus dem Verein"},
    {"/termine", "Termine", "Alle Veranstaltungen, auch zum Abonnieren"},
    {"/verein", "Verein", "Über uns, Vorstand, Offiziere und mehr"}
  ]

  # The full-layout 404 page (BbhWeb.NotFoundHTML). Every pipeline that reaches here —
  # :browser for a missing record, :not_found for the catch-all — has fetched the
  # session and scope, set the root layout and the CSP nonce the layout relies on.
  defp render_404(conn) do
    conn
    |> put_status(:not_found)
    |> put_format("html")
    |> put_view(BbhWeb.NotFoundHTML)
    |> render(:not_found,
      page_title: "Seite nicht gefunden",
      flash: conn.assigns[:flash] || %{},
      current_scope: conn.assigns[:current_scope],
      query: BbhWeb.NotFoundHTML.suggested_query(conn.request_path),
      links: @links
    )
    |> halt()
  end

  defp maybe_log(conn) do
    path = conn.request_path

    if conn.method == "GET" and loggable?(path) do
      referrer = external_referrer(conn)
      dispatch(fn -> Redirects.record_not_found(path, referrer) end)
    end

    :ok
  end

  # The ignore list lives in Bbh.Redirects so the nightly prune applies the same rules;
  # checking here as well spares a task for every scanner probe.
  defp loggable?(path), do: not Redirects.ignored_not_found?(path)

  defp external_referrer(conn) do
    with [referer | _] <- get_req_header(conn, "referer"),
         %URI{host: host} when is_binary(host) <- URI.parse(referer),
         true <- host != conn.host do
      referer
    else
      _ -> nil
    end
  end

  defp dispatch(fun) do
    if Application.get_env(:bbh, __MODULE__, [])[:async] == false do
      fun.()
    else
      Task.Supervisor.start_child(Bbh.TaskSupervisor, fun)
    end
  end
end
