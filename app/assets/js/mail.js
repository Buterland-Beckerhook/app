// Turns an obfuscated e-mail anchor into a real mailto: link.
//
// The server renders the address split into chunks with `.eml-x` decoys woven in
// (see BbhWeb.EmailObfuscation). Reassembling it means walking the `.eml` container
// and skipping those decoys — there is no encoded payload and no key, the address
// simply never exists as one string in the markup.
//
// Two deliberate choices:
//
//   * The href is rewritten on the first *interaction*, not on load. A scraper that
//     renders the page and harvests hrefs finds the contact-form fallback.
//   * Listeners are delegated on `document` in the capture phase. The public site is
//     served as dead views, so a phx-hook would never fire there, and the CSP has no
//     'unsafe-inline' for scripts — an inline handler would be blocked in production
//     (see lib/bbh_web/plugs/csp.ex).

// Recursive, not a filter over the direct children: a decoy may sit at any depth, and
// a flat filter would fold nested junk into the address via textContent.
function visibleText(node) {
  if (node.nodeType !== Node.ELEMENT_NODE) return node.textContent
  if (node.classList.contains("eml-x")) return ""

  return Array.from(node.childNodes).map(visibleText).join("")
}

function address(anchor) {
  return visibleText(anchor.querySelector(".eml") || anchor)
}

function hydrate(anchor) {
  if (anchor.dataset.emlReady) return

  const value = address(anchor).trim()
  if (!value.includes("@")) return // leave the contact-form fallback, and retry later

  anchor.href = `mailto:${value}${anchor.dataset.eml || ""}`
  anchor.dataset.emlReady = "1"
}

// pointerdown / touchstart / focusin all fire before the link is activated, so by the
// time the click or Enter lands the href is already the real one.
for (const event of ["pointerdown", "touchstart", "focusin"]) {
  document.addEventListener(
    event,
    (e) => {
      const anchor = e.target.closest?.("a[data-eml]")
      if (anchor) hydrate(anchor)
    },
    true,
  )
}

// Safety net for activations that skip those events (synthetic clicks, some
// assistive tech): hydrate late and navigate ourselves.
document.addEventListener("click", (e) => {
  const anchor = e.target.closest?.("a[data-eml]")
  if (!anchor || anchor.dataset.emlReady) return

  hydrate(anchor)
  e.preventDefault()
  window.location.href = anchor.href
})
