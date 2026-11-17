defmodule Bbh.Dashboard do
  @moduledoc """
  The figures on the admin start page, gathered from the contexts that own them, so the
  page itself asks one module instead of every context. Read-only; who may see what is
  decided by the caller (`BbhWeb.Admin.DashboardLive` via `Bbh.Authz`).
  """

  alias Bbh.Accounts.Scope

  @doc "Content totals by status (people: one count), for the stat cards."
  def content_counts do
    %{
      articles: Bbh.Content.count_articles_by_status(),
      events: Bbh.Calendar.count_events_by_status(),
      people: Bbh.Club.count_people(),
      pages: Bbh.Content.Pages.count_pages_by_status()
    }
  end

  @doc "The Postfach widget: new tickets in the scope's queues and the ones assigned to it."
  def tickets(%Scope{} = scope) do
    %{new: Bbh.Tickets.count_new(scope), mine: Bbh.Tickets.list_assigned(scope)}
  end

  @doc """
  Visitor analytics for the last `days` days up to today (UTC). The basic figures are
  for every staff member; `full?` adds iCal, push, referrers and search terms (admins).
  """
  def analytics(days, full?) when is_integer(days) and days > 0 do
    to = Date.utc_today()
    from = Date.add(to, -(days - 1))

    basic = %{
      summary: Bbh.Analytics.summary(from, to),
      by_day: Bbh.Analytics.views_by_day(from, to),
      top_pages: Bbh.Analytics.top_pages(from, to),
      top_articles: Bbh.Analytics.top_articles(from, to)
    }

    if full? do
      Map.merge(basic, %{
        ical: Bbh.Analytics.ical_summary(from, to),
        ical_clients: Bbh.Analytics.ical_clients(from, to),
        push_subscriptions: Bbh.Notifications.count_subscriptions(),
        top_referrers: Bbh.Analytics.top_referrers(from, to),
        top_searches: Bbh.Analytics.top_searches(from, to)
      })
    else
      basic
    end
  end
end
