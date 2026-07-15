// Live countdown for the homepage "Nächster Termin" banner.
//
// Progressively enhances any element carrying `data-countdown-to` with a naive
// (timezone-less) ISO target, e.g. "2026-07-18T00:00:00". The string is parsed
// as local time — matching how the site renders event times — and the child
// `[data-cd="days|hours|minutes|seconds"]` slots are updated once per second.
function initCountdown() {
  const el = document.querySelector("[data-countdown-to]")
  if (!el) return

  const target = new Date(el.dataset.countdownTo).getTime()
  if (Number.isNaN(target)) return

  const slot = (unit) => el.querySelector(`[data-cd="${unit}"]`)
  const slots = {
    days: slot("days"),
    hours: slot("hours"),
    minutes: slot("minutes"),
    seconds: slot("seconds"),
  }
  const pad = (n) => String(n).padStart(2, "0")

  const tick = () => {
    let diff = Math.max(0, Math.floor((target - Date.now()) / 1000))
    const d = Math.floor(diff / 86400)
    diff -= d * 86400
    const h = Math.floor(diff / 3600)
    diff -= h * 3600
    const m = Math.floor(diff / 60)
    const s = diff - m * 60

    if (slots.days) slots.days.textContent = String(d)
    if (slots.hours) slots.hours.textContent = pad(h)
    if (slots.minutes) slots.minutes.textContent = pad(m)
    if (slots.seconds) slots.seconds.textContent = pad(s)
  }

  tick()
  window.setInterval(tick, 1000)
}

if (document.readyState === "loading") {
  document.addEventListener("DOMContentLoaded", initCountdown)
} else {
  initCountdown()
}
