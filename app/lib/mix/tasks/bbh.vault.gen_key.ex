defmodule Mix.Tasks.Bbh.Vault.GenKey do
  @shortdoc "Print a new Postfach encryption key (base64, 32 bytes)"
  @moduledoc """
  Prints a fresh key for `TICKET_KEYS` / `TICKET_HMAC_KEY` (`Bbh.Vault`).

      mix bbh.vault.gen_key

  Store it in the club password manager before putting it into the server's `.env`.
  """
  use Mix.Task

  @requirements ["compile"]

  @impl true
  def run(_args), do: Mix.shell().info(Bbh.Vault.generate_key())
end
