// Busy state for the public dead-view forms (Kontakt, Mitgliedsantrag).
//
// The server sends the club mail before it answers, which can take a few seconds. A
// `<form data-busy>` disables its submit button and swaps the button content for the
// `data-busy-label` text with a spinner, so the wait reads as "sending" and a second
// click cannot post the form twice. Bound on `document` like membership.js (no inline
// scripts under the CSP).

const SPINNER = '<span class="loading loading-spinner loading-sm" aria-hidden="true"></span>'

document.addEventListener("submit", (e) => {
  const form = e.target
  // Bubble phase: a listener on the form itself (e.g. the altcha widget holding the
  // submit until it is verified) has already run and may have cancelled it.
  if (!(form instanceof HTMLFormElement) || !form.hasAttribute("data-busy") || e.defaultPrevented) return

  for (const button of form.querySelectorAll("button[type=submit][data-busy-label]")) {
    button.dataset.idleHtml = button.innerHTML
    button.innerHTML = `${SPINNER} ${button.dataset.busyLabel}`
    button.disabled = true
    button.setAttribute("aria-busy", "true")
  }
})

// Back navigation may restore the page from the bfcache with the button still busy.
window.addEventListener("pageshow", (e) => {
  if (!e.persisted) return
  for (const button of document.querySelectorAll("form[data-busy] button[data-idle-html]")) {
    button.innerHTML = button.dataset.idleHtml
    delete button.dataset.idleHtml
    button.disabled = false
    button.removeAttribute("aria-busy")
  }
})
