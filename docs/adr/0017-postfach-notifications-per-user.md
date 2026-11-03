# ADR 0017 — Postfach notifications are per user: interval, channel and push devices

**Status:** Accepted (2026-11-03)

## Context

Every new request reached its queue's staff as a mail within two minutes, each reply
at once. Fine for someone who works the Postfach daily, noisy for someone who looks in
now and then, and silent on a phone without the mail app's notifications. A marker on
the ticket (`notified_at`) can only say "the queue was told", not "this person was".

## Decision

- **An outbox per user** (`ticket_notifications`: user, ticket, kind; ids only). The
  two-minute worker fills it and flushes what is due (`Bbh.Tickets.Alerts`). Whether a
  row still matters is decided when it is sent, so a request taken while collecting is
  never announced. `tickets.notified_at` stays: it now means "in the outbox".
- **Intervals are fixed times, counted from the end of the quiet hours.** With 22–8,
  "every 4 hours" is 8, 12, 16 and 20 o'clock: the first message of the day carries the
  night's requests. "Once a day" is the exception, 19 o'clock (the last active hour if
  that is quiet), when a volunteer has time for it. The list ends at once a day. The
  default stays every run, within two minutes.
- **Reminders travel in the same message**, at the user's first time at or after the
  reminder hour and at most once a day (`users.ticket_reminded_on`), so "once a day"
  stays one message. They are worked out when sent, so a request taken since is gone.
- **Quiet hours stay one site-wide window** and now cover Postfach mail and push. They
  hold everything back, so nothing is lost. Assignments wait too.
- **The channel is mail, push or both.** Push-only with no device taking the message
  falls back to mail. The admin digest stays mail: it is a report, not a notification.
- **A device is a push subscription with an owner** (`push_subscriptions.user_id`). A
  browser has exactly one subscription per site, so there is no "second subscription":
  one row carries the public categories and the Postfach. Consequences: linking takes
  the session (`POST /push/postfach`, strong auth + Postfach access) while knowing the
  endpoint proves the device; turning off the public part keeps a linked device
  (`unsubscribe` answers `kept`, and the browser must not drop its subscription);
  devices without categories stay out of the "Alle Abonnenten" broadcast. A browser can
  only subscribe itself, so each device is set up once on the device.
- **Pushes carry what the mails carry:** queue, reference, link. They survive logging
  out on purpose — that is when they are useful — and say nothing worth protecting.

## Consequences

- Replies now wait for the next worker run (up to two minutes) instead of going out
  while the mail is imported.
- At night nobody hears about a request until the window ends, however urgent.
- A device stays linked until removed on the settings page, or until its push service
  reports it gone.
