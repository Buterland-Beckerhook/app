// Pure helpers for the push-notification settings (no DOM, unit-tested in
// push_state.test.js). push.js gathers the browser facts and renders the result.

export const CATEGORIES = [
  {value: "termine", label: "Termine"},
  {value: "news", label: "Neue Beiträge"},
]

const label = (value) => CATEGORIES.find((c) => c.value === value)?.label || value

// Reduce what the browser and the server report to one of a few states:
//   unsupported   — no Service Worker / Push API in this browser
//   install       — iOS Safari outside an installed web app (push only works there)
//   denied        — the user blocked notifications for this site
//   off           — no subscription in this browser, or the server no longer has it
//   on            — subscribed; `categories` says for what
//
// `server` is the /api/push/status answer, or null when there is no browser
// subscription to ask about.
export function pushState({supported, iosNeedsInstall, permission, server}) {
  if (iosNeedsInstall) return {kind: "install"}
  if (!supported) return {kind: "unsupported"}
  if (permission === "denied") return {kind: "denied"}
  if (server && server.subscribed && server.categories.length > 0) {
    return {kind: "on", categories: server.categories, tester: !!server.tester}
  }
  return {kind: "off"}
}

// The sentence shown in the settings dialog.
export function statusText(state) {
  switch (state.kind) {
    case "install":
      return 'Auf iPhone und iPad gibt es Benachrichtigungen nur, wenn die Seite installiert ist: im Teilen-Menü „Zum Home-Bildschirm" wählen und von dort öffnen.'
    case "unsupported":
      return "Dieser Browser unterstützt keine Push-Benachrichtigungen."
    case "denied":
      return "Benachrichtigungen sind für diese Seite im Browser blockiert. Bitte in den Website-Einstellungen des Browsers erlauben."
    case "on":
      return `Aktiv auf diesem Gerät für: ${state.categories.map(label).join(", ")}.`
    default:
      return "Auf diesem Gerät sind keine Benachrichtigungen aktiv."
  }
}

// The footer link text.
export function footerLabel(state) {
  return state.kind === "on" ? "Benachrichtigungen: aktiv" : "Benachrichtigungen"
}
