defmodule BbhWeb.UserLive.LoginPasskeyTest do
  # async: false — installs a global Wax stub via Application env.
  use BbhWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Bbh.AccountsFixtures

  setup do
    Bbh.WaxStub.install(&on_exit/1)
    :ok
  end

  defp assertion_params(credential_id) do
    %{
      "rawId" => Base.url_encode64(credential_id, padding: false),
      "authenticatorData" => Base.url_encode64("ad", padding: false),
      "signature" => Base.url_encode64("sig", padding: false),
      "clientDataJSON" => Base.url_encode64("cdj", padding: false)
    }
  end

  test "renders passkey options into the hook up front", %{conn: conn} do
    {:ok, _lv, html} = live(conn, ~p"/users/log-in")

    # The challenge is minted on the connected mount and embedded in the DOM, so
    # the click handler can call WebAuthn synchronously (no server round-trip) and
    # Safari keeps the user-activation window it needs to reach an extension.
    assert html =~ ~s(data-passkey-ceremony="get")
    assert html =~ "data-passkey-options"
    assert html =~ "challenge"
  end

  test "a valid passkey assertion arms the login handoff form", %{conn: conn} do
    user = user_fixture()
    cid = :crypto.strong_rand_bytes(16)
    passkey_fixture(user, credential_id: cid, sign_count: 0)
    Bbh.WaxStub.put_authentication({:ok, %{sign_count: 1}})

    {:ok, lv, _html} = live(conn, ~p"/users/log-in")

    html = render_hook(lv, "passkey_login_assertion", assertion_params(cid))

    # The hidden handoff form is triggered (phx-trigger-action rendered) to POST
    # the signed token to the session controller.
    assert html =~ "phx-trigger-action"
  end

  test "sudo re-auth rejects a passkey belonging to a different account", %{conn: conn} do
    signed_in = user_fixture()
    other = user_fixture()
    cid = :crypto.strong_rand_bytes(16)
    passkey_fixture(other, credential_id: cid, sign_count: 0)
    Bbh.WaxStub.put_authentication({:ok, %{sign_count: 1}})

    # Log in as `signed_in`; the login page is now the sudo re-auth page.
    conn = log_in_user(conn, signed_in)
    {:ok, lv, _html} = live(conn, ~p"/users/log-in")

    html = render_hook(lv, "passkey_login_assertion", assertion_params(cid))

    assert html =~ "anderen Konto"
    refute html =~ "phx-trigger-action"
  end
end
