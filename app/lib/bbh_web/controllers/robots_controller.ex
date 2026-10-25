defmodule BbhWeb.RobotsController do
  @moduledoc """
  `/robots.txt`. Dynamic rather than a static file so the beta can turn every crawler
  away (`BbhWeb.Beta`) while the live site points them at its sitemap.
  """
  use BbhWeb, :controller

  # AI crawlers named explicitly on the beta: `*` already covers them, but some only
  # act on a group addressed to them by name.
  @ai_agents ~w(GPTBot ChatGPT-User OAI-SearchBot ClaudeBot Claude-User Claude-SearchBot
                anthropic-ai Google-Extended Applebot-Extended PerplexityBot Perplexity-User
                CCBot Bytespider meta-externalagent Amazonbot cohere-ai Diffbot)

  # sobelow_skip ["XSS.SendResp"]
  # Served as text/plain; the only interpolated values are our own config and constants.
  def index(conn, _params) do
    conn
    |> put_resp_content_type("text/plain")
    |> send_resp(200, body(BbhWeb.Beta.enabled?()))
  end

  defp body(true) do
    named = Enum.map_join(@ai_agents, "\n", &"User-agent: #{&1}\nDisallow: /\n")

    """
    # Beta-Version – bitte nicht indexieren. Die echte Seite: #{BbhWeb.Beta.live_url("/")}
    User-agent: *
    Disallow: /

    #{named}\
    """
  end

  defp body(false) do
    """
    User-agent: *
    Allow: /
    Disallow: /admin
    Disallow: /users

    Sitemap: #{BbhWeb.ControllerHelpers.site_url()}/sitemap.xml
    """
  end
end
