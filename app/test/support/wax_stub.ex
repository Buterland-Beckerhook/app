defmodule Bbh.WaxStub do
  @moduledoc """
  Test double for the `Wax` crypto edge used by `Bbh.Accounts.Passkeys`.

  Real WebAuthn assertions can't be forged without a genuine authenticator, so
  tests inject this module via `Application.put_env(:bbh, :wax_module, ...)` and
  set the canned return values with `put_registration/1` / `put_authentication/1`.
  """

  def register(_attestation_object, _client_data_json, _challenge) do
    Application.get_env(:bbh, :wax_stub_registration, {:error, :not_configured})
  end

  def authenticate(_credential_id, _auth_data, _sig, _client_data_json, _challenge, _credentials) do
    Application.get_env(:bbh, :wax_stub_authentication, {:error, :not_configured})
  end

  @doc "Configure the `register/3` return value."
  def put_registration(result), do: Application.put_env(:bbh, :wax_stub_registration, result)

  @doc "Configure the `authenticate/6` return value."
  def put_authentication(result), do: Application.put_env(:bbh, :wax_stub_authentication, result)

  @doc "Install the stub and reset canned results; restores on test exit."
  def install(on_exit) do
    previous = Application.get_env(:bbh, :wax_module)
    Application.put_env(:bbh, :wax_module, __MODULE__)

    on_exit.(fn ->
      # Always restore: when there was no prior value the context must fall back
      # to the real `Wax`, otherwise the stub leaks into other tests.
      case previous do
        nil -> Application.delete_env(:bbh, :wax_module)
        module -> Application.put_env(:bbh, :wax_module, module)
      end

      Application.delete_env(:bbh, :wax_stub_registration)
      Application.delete_env(:bbh, :wax_stub_authentication)
    end)
  end
end
