// Auto-dismiss flash toasts when their countdown bar (.flash-progress) finishes.
//
// Plain JS (no LiveView hook) so it works on server-rendered "dead" pages too —
// the contact form and other controller responses render flashes outside any
// LiveView, where phx-hook never mounts. Same progressive-enhancement approach as
// the lightbox/countdown enhancers.
//
// Hover/focus pausing is pure CSS (animation-play-state, see app.css). Dismissal
// always fades the node out and removes it directly, so the toast is guaranteed to
// disappear when the countdown ends. On LiveView pages we additionally fire the
// toast's own phx-click via liveSocket.execJS to clear the flash server-side (so a
// later patch can't re-render it) — but we never rely on that round-trip for the
// visual removal, because an interrupting patch or a not-yet-connected socket can
// leave the toast stuck on screen.
//
// Dismissal is triggered by three independent, overlapping paths so a toast can
// never get stranded: (1) an owned, pause-aware timer; (2) the bar's `animationend`
// as a redundant backstop if that timer is ever lost; and (3) a hard lifetime
// ceiling so hover/focus (e.g. a patch parking focus in the toast) can pause it but
// never forever. dismissFlash is idempotent, so all three can fire safely.

const FLASH_SELECTOR = "[role='alert']"
// Elements rendered inside a LiveView carry one of these container attributes;
// controller-rendered dead pages carry none, which is how we route dismissal.
const LIVEVIEW_CONTAINER = "[data-phx-main],[data-phx-session],[data-phx-root-id]"

function dismissFlash(el) {
  // Idempotent: multiple triggers (owned timer, animationend, hard ceiling) may all
  // fire for the same toast — only the first does the work.
  if (el._flashDismissed) return
  el._flashDismissed = true
  clearInterval(el._flashTimer)

  // Clear the server-side flash on LiveView pages so it can't reappear on the next
  // patch. Fire-and-forget — the visual removal below runs regardless.
  if (window.liveSocket && el.closest(LIVEVIEW_CONTAINER)) {
    try {
      window.liveSocket.execJS(el, el.getAttribute("phx-click"))
    } catch (_err) {
      // No usable owning view — the direct fade-out below still hides the toast.
    }
  }

  // Always fade out and remove the node directly. (Harmless no-op if a server
  // re-render already removed it.)
  el.style.transition = "opacity 200ms ease-in"
  el.style.opacity = "0"
  window.setTimeout(() => el.remove(), 220)
}

function flashDuration(el) {
  const raw = getComputedStyle(el).getPropertyValue("--flash-duration").trim()
  const ms = parseFloat(raw)
  if (!ms) return 6000
  return raw.endsWith("ms") ? ms : ms * 1000
}

function armFlash(el) {
  const bar = el.querySelector(".flash-progress")
  if (!bar) return

  // A toast that was already dismissed (node removed by us) but got resurrected by a
  // LiveView patch — its server flash hasn't cleared yet. Dismiss it again straight
  // away rather than granting a fresh countdown, so it can't linger cycle after cycle.
  if (el._flashDismissed) return dismissFlash(el)

  // Restart the visual bar so a re-used toast node (same id, new message) counts
  // down afresh rather than inheriting the previous, nearly-finished bar.
  bar.style.animation = "none"
  void bar.offsetWidth
  bar.style.animation = ""

  // Redundant dismissal: whatever happens to the JS timer below (a LiveView patch
  // dropping the node, a throttled background tab), when the CSS bar visibly finishes
  // we also dismiss. One-shot, and re-attached on every (re)arm so a patch that
  // replaces the bar node can't leave us without a listener.
  if (bar._flashOnEnd) bar.removeEventListener("animationend", bar._flashOnEnd)
  bar._flashOnEnd = () => dismissFlash(el)
  bar.addEventListener("animationend", bar._flashOnEnd, {once: true})

  // Drive dismissal with a pause-aware timer that mirrors the CSS bar's hover/focus
  // pause. A hard ceiling (well past the normal duration) guarantees the toast can
  // never hang forever if it stays hovered or a patch parks focus inside it — the
  // usual failure that left toasts stuck on screen.
  clearInterval(el._flashTimer)
  const duration = flashDuration(el)
  let remaining = duration
  let last = Date.now()
  const hardDeadline = last + duration * 4
  el._flashTimer = setInterval(() => {
    // Toast already gone (closed, navigated away) — stop ticking.
    if (!el.isConnected) return clearInterval(el._flashTimer)
    const now = Date.now()
    if (!el.matches(":hover, :focus-within")) remaining -= now - last
    last = now
    if (remaining <= 0 || now >= hardDeadline) {
      clearInterval(el._flashTimer)
      dismissFlash(el)
    }
  }, 100)
}

function scanForFlashes(node) {
  if (!node || node.nodeType !== 1) return

  if (node.matches && node.matches(FLASH_SELECTOR) && node.querySelector(".flash-progress")) {
    armFlash(node)
  }

  if (node.querySelectorAll) {
    node.querySelectorAll(FLASH_SELECTOR).forEach((el) => {
      if (el.querySelector(".flash-progress")) armFlash(el)
    })
  }
}

function armEnclosingFlash(target) {
  const node = target.nodeType === 1 ? target : target.parentElement
  const toast = node && node.closest && node.closest(FLASH_SELECTOR)
  if (toast && toast.querySelector(".flash-progress")) armFlash(toast)
}

function initFlashAutoHide() {
  const container = document.getElementById("flash-group") || document.body
  scanForFlashes(container)

  // LiveView may add a fresh flash node (childList) or patch an existing one's
  // text in place (characterData) on a subsequent message — re-arm in both cases.
  const observer = new MutationObserver((mutations) => {
    for (const mutation of mutations) {
      if (mutation.type === "childList") {
        mutation.addedNodes.forEach((node) => {
          // A freshly added toast (top-level) or an inner part a patch re-created
          // (e.g. the .flash-progress bar) — re-arm in both cases so the owned
          // timer is never left dangling.
          scanForFlashes(node)
          armEnclosingFlash(node)
        })
      } else {
        armEnclosingFlash(mutation.target)
      }
    }
  })
  observer.observe(container, {childList: true, subtree: true, characterData: true})
}

if (document.readyState === "loading") {
  document.addEventListener("DOMContentLoaded", initFlashAutoHide)
} else {
  initFlashAutoHide()
}
