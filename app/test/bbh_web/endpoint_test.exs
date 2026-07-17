defmodule BbhWeb.EndpointTest do
  # async: false — the request-logging test toggles the global Logger level.
  use BbhWeb.ConnCase, async: false

  import ExUnit.CaptureLog

  describe "log_level/1" do
    test "health probe paths log at :debug" do
      assert BbhWeb.Endpoint.log_level(%Plug.Conn{request_path: "/health/liveness"}) == :debug
      assert BbhWeb.Endpoint.log_level(%Plug.Conn{request_path: "/health/readiness"}) == :debug
    end

    test "every other path logs at :info" do
      assert BbhWeb.Endpoint.log_level(%Plug.Conn{request_path: "/"}) == :info
      assert BbhWeb.Endpoint.log_level(%Plug.Conn{request_path: "/articles"}) == :info
      # A prefix match alone is not enough — the trailing slash is required, so
      # a hypothetical "/healthz" route would still log at :info.
      assert BbhWeb.Endpoint.log_level(%Plug.Conn{request_path: "/healthz"}) == :info
    end
  end

  describe "request logging" do
    setup do
      previous = Logger.level()
      # Raise the primary level so :debug messages reach the capture handler;
      # the handler's own :level option is what we assert on below.
      Logger.configure(level: :debug)
      on_exit(fn -> Logger.configure(level: previous) end)
      :ok
    end

    test "health probes are logged at :debug, hidden at :info", %{conn: conn} do
      # Captured when the threshold is :debug ...
      at_debug = capture_log([level: :debug], fn -> get(conn, "/health/liveness") end)
      assert at_debug =~ "GET /health/liveness"

      # ... but absent at :info, so prod logs at the default level stay clean.
      # (This also proves the MFA is wired: without it the probe would log at the
      # default :info and show up here. The :info default for non-health paths is
      # covered by the log_level/1 unit tests above — no non-health route reaches
      # Plug.Telemetry without the DB: static files are served before it, pages
      # need the DB, and a 404 raises in ConnTest.)
      at_info = capture_log([level: :info], fn -> get(conn, "/health/liveness") end)
      refute at_info =~ "/health/liveness"
    end
  end
end
