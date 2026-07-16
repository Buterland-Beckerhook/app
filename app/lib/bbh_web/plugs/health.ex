defmodule BbhWeb.Plugs.Health do
  @moduledoc """
  Lightweight health endpoints for container/proxy probes, mounted in the
  endpoint before the router so they bypass session/parsing overhead.

    * `GET /health/liveness`  — always 200 while the VM is up.
    * `GET /health/readiness` — 200 when the DB answers `SELECT 1`, else 503.

  Any other request path is passed through untouched.
  """
  import Plug.Conn

  def init(opts), do: opts

  def call(%Plug.Conn{request_path: "/health/liveness"} = conn, _opts) do
    conn |> put_resp_content_type("text/plain") |> send_resp(200, "OK") |> halt()
  end

  def call(%Plug.Conn{request_path: "/health/readiness"} = conn, _opts) do
    conn = put_resp_content_type(conn, "text/plain")

    case check_db() do
      :ok -> conn |> send_resp(200, "OK") |> halt()
      :error -> conn |> send_resp(503, "DB unavailable") |> halt()
    end
  end

  def call(conn, _opts), do: conn

  defp check_db do
    case Ecto.Adapters.SQL.query(Bbh.Repo, "SELECT 1", []) do
      {:ok, _} -> :ok
      _ -> :error
    end
  rescue
    _ -> :error
  end
end
