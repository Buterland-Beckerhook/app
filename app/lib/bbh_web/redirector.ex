defmodule BbhWeb.Redirector do
  @moduledoc """
  The site's single 404 path. Every "not found" — no route matched
  (`BbhWeb.NotFoundController`), or a controller found no record
  (`BbhWeb.ControllerHelpers.not_found/1`) — ends here, which:

    1. redirects when `Bbh.Redirects.resolve/1` knows a target (GET/HEAD only), else
    2. records the path in the 404 log (`Bbh.Redirects.record_not_found/2`) and
    3. renders the 404 page.

  Because redirects are only looked up here, a rule can never shadow a live page.

  Config (`config :bbh, __MODULE__, ...`): `async: false` writes the 404 log inline
  instead of via `Bbh.TaskSupervisor` (tests, so the write stays in the SQL sandbox).
  """
  import Plug.Conn
  import Phoenix.Controller

  alias Bbh.Redirects

  # Areas whose 404s say nothing about missing redirects, or whose paths carry secrets
  # (revoked calendar-share tokens) that do not belong in a log.
  @skip_log_prefixes ~w(/admin /users /api /dev /assets /images /fonts /media /oauth /mcp
                        /kalender/geteilt /.well-known /live /phoenix)

  # Vulnerability scanners probing for other software. Logging them would bury the
  # handful of real old links under noise.
  @scanner_re ~r{/\.|\.(php\d?|aspx?|jsp|cgi|env|ini|sql|bak|old|swp|zip|tar|gz|rar|7z|log|ya?ml|config)$|wp-|xmlrpc|phpmyadmin|cgi-bin}i

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

  defp render_404(conn) do
    conn
    |> put_status(:not_found)
    |> put_format("html")
    |> put_view(BbhWeb.ErrorHTML)
    |> render(:"404")
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

  defp loggable?(path) do
    not Enum.any?(@skip_log_prefixes, &(path == &1 or String.starts_with?(path, &1 <> "/"))) and
      not Regex.match?(@scanner_re, path)
  end

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
