defmodule Bbh.SiteTest do
  use ExUnit.Case, async: true

  # Passkeys verify the browser's origin against Bbh.Site, while the browser is at the
  # endpoint's URL: the two configs must agree (as they do in runtime.exs for prod).
  test "matches the endpoint's URL" do
    assert Bbh.Site.url() == BbhWeb.Endpoint.url()
    assert Bbh.Site.host() == BbhWeb.Endpoint.host()
  end
end
