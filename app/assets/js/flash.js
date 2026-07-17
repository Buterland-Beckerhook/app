// Auto-dismiss flash toasts when their countdown bar (.flash-progress) finishes.
//
// Plain JS (no LiveView hook) so it works on server-rendered "dead" pages too —
// the contact form and other controller responses render flashes outside any
// LiveView, where phx-hook never mounts. Same progressive-enhancement approach as
// the lightbox/countdown enhancers.
//
// Hover/focus pausing is pure CSS (animation-play-state, see app.css). Dismissal:
//   - LiveView pages: run the toast's own phx-click via liveSocket.execJS, which
//     clears the flash on the server AND runs the hide transition.
//   - Dead pages: liveSocket.execJS has no owning view and silently no-ops, so we
//     fade the toast out directly instead. (The server flash is already consumed
//     on the redirect, so there is nothing to clear server-side.)

const FLASH_SELECTOR = "[role='alert']"
// Elements rendered inside a LiveView carry one of these container attributes;
// controller-rendered dead pages carry none, which is how we route dismissal.
const LIVEVIEW_CONTAINER = "[data-phx-main],[data-phx-session],[data-phx-root-id]"

function dismissFlash(el) {
  if (window.liveSocket && el.closest(LIVEVIEW_CONTAINER)) {
    try {
      window.liveSocket.execJS(el, el.getAttribute("phx-click"))
      return
    } catch (_err) {
      // No usable owning view — fall through to a direct fade-out.
    }
  }

  el.style.transition = "opacity 200ms ease-in"
  el.style.opacity = "0"
  window.setTimeout(() => el.remove(), 220)
}

function armFlash(el) {
  const bar = el.querySelector(".flash-progress")
  if (!bar) return

  // Restart the animation so a re-used toast node (same id, new message) counts
  // down afresh rather than inheriting the previous, nearly-finished bar.
  bar.style.animation = "none"
  void bar.offsetWidth
  bar.style.animation = ""

  if (el._flashOnEnd) bar.removeEventListener("animationend", el._flashOnEnd)
  el._flashOnEnd = () => dismissFlash(el)
  bar.addEventListener("animationend", el._flashOnEnd)
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
        mutation.addedNodes.forEach(scanForFlashes)
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
