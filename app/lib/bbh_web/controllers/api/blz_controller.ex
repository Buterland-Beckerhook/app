defmodule BbhWeb.Api.BlzController do
  @moduledoc """
  IBAN → BIC/Kreditinstitut lookup for the membership form's live auto-fill.

  Returns only public bank-directory data (Bundesbank BLZ file). An unknown or
  non-German IBAN yields `{}` so the client simply leaves the fields blank.
  """
  use BbhWeb, :controller

  alias BbhWeb.RateLimit

  def show(conn, %{"iban" => iban}) do
    case RateLimit.check("blz_lookup", RateLimit.client_ip(conn), 60, :timer.minutes(1)) do
      :ok ->
        case Bbh.Blz.lookup_by_iban(iban) do
          {:ok, %{bic: bic, name: name}} -> json(conn, %{bic: bic, kreditinstitut: name})
          :error -> json(conn, %{})
        end

      {:error, _retry_after} ->
        conn |> put_status(:too_many_requests) |> json(%{})
    end
  end

  def show(conn, _params), do: json(conn, %{})
end
