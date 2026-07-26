// Progressive enhancement for the public membership form (/verein/mitglied-werden).
//
// The public site is served as dead views (no LiveView) and the CSP forbids inline
// scripts, so — unlike the admin `DatePicker` phx-hook — this behavior lives in the
// bundle and hangs off `document`. It does three things:
//
//   1. Turns the date fields into the site's German flatpickr picker (TT.MM.JJJJ).
//   2. Shows a *soft* age hint (min age for members, max age for listed children).
//      Nothing is blocked; the club mail also flags an out-of-range entry server-side.
//   3. Grows the "Kinder" section: filling the last row appends a fresh one (no cap).

// Completed years from a "TT.MM.JJJJ" or ISO date string, or null if unparseable.
function calcAge(str) {
  if (!str) return null
  const iso = str.match(/^(\d{4})-(\d{2})-(\d{2})$/)
  const de = str.match(/^(\d{1,2})\.(\d{1,2})\.(\d{4})$/)
  let y, m, d
  if (iso) [, y, m, d] = iso.map(Number)
  else if (de) [, d, m, y] = de.map(Number)
  else return null

  const today = new Date()
  let age = today.getFullYear() - y
  if (today.getMonth() + 1 < m || (today.getMonth() + 1 === m && today.getDate() < d)) age--
  return age
}

// Toggle the sibling hint when the entered age falls outside the configured bounds.
function checkAgeHint(input) {
  const hint = input.parentElement?.querySelector("[data-age-hint]")
  if (!hint) return
  const age = calcAge(input.value)
  const min = input.dataset.minAge
  const max = input.dataset.maxAge
  const outOfRange =
    age != null && ((min != null && age < Number(min)) || (max != null && age >= Number(max)))
  hint.hidden = !outOfRange
}

function initDateField(input) {
  if (input._fpInit) return
  input._fpInit = true

  if (window.flatpickr) {
    window.flatpickr(input, {
      locale: "de",
      allowInput: true,
      dateFormat: "d.m.Y",
      maxDate: "today",
      onChange: () => {
        // Let the "grow children" listener see selections too, then re-check the hint.
        input.dispatchEvent(new Event("input", {bubbles: true}))
        checkAgeHint(input)
      },
    })
  }
  input.addEventListener("change", () => checkAgeHint(input))
  input.addEventListener("blur", () => checkAgeHint(input))
}

// Fill an empty BIC / Kreditinstitut from the entered IBAN via the local BLZ lookup.
// Same-origin fetch (allowed by connect-src 'self'); anything the applicant typed is
// left untouched, and an unknown IBAN or unavailable lookup just leaves the fields blank.
async function fillBankFromIban() {
  const ibanInput = document.getElementById("iban")
  if (!ibanInput) return
  const iban = ibanInput.value.replace(/\s+/g, "").toUpperCase()
  if (!/^DE\d{20}$/.test(iban)) return

  const bic = document.getElementById("bic")
  const inst = document.getElementById("kreditinstitut")
  if (bic?.value.trim() && inst?.value.trim()) return

  try {
    const res = await fetch(`/api/blz?iban=${encodeURIComponent(iban)}`, {
      headers: {Accept: "application/json"},
    })
    if (!res.ok) return
    const data = await res.json()
    if (bic && !bic.value.trim() && data.bic) bic.value = data.bic
    if (inst && !inst.value.trim() && data.kreditinstitut) inst.value = data.kreditinstitut
  } catch {
    // Offline or lookup unavailable — the server backfills on submit anyway.
  }
}

document.addEventListener("DOMContentLoaded", () => {
  document.querySelectorAll("[data-flatpickr]").forEach(initDateField)

  const ibanInput = document.getElementById("iban")
  if (ibanInput) {
    let timer
    ibanInput.addEventListener("input", () => {
      clearTimeout(timer)
      timer = setTimeout(fillBankFromIban, 400)
    })
  }
})

document.addEventListener("input", (e) => {
  const container = e.target.closest?.("[data-children]")
  if (!container) return

  const rows = container.querySelectorAll("[data-child-row]")
  const last = rows[rows.length - 1]
  // Only grow when the edit lands in the current last row and leaves it non-empty.
  if (!last || !last.contains(e.target)) return

  const filled = Array.from(last.querySelectorAll("input")).some((i) => i.value.trim() !== "")
  if (!filled) return

  const template = container.querySelector("[data-child-template]")
  if (!template) return

  const row = template.content.firstElementChild.cloneNode(true)
  container.insertBefore(row, template)
  row.querySelectorAll("[data-flatpickr]").forEach(initDateField)
})
