// If you want to use Phoenix channels, run `mix help phx.gen.channel`
// to get started and then uncomment the line below.
// import "./user_socket.js"

// You can include dependencies in two ways.
//
// The simplest option is to put them in assets/vendor and
// import them using relative paths:
//
//     import "../vendor/some-package.js"
//
// Alternatively, you can `npm install some-package --prefix assets` and import
// them using a path starting with the package name:
//
//     import "some-package"
//
// If you have dependencies that try to import CSS, esbuild will generate a separate `app.css` file.
// To load it, simply add a second `<link>` to your `root.html.heex` file.

// Include phoenix_html to handle method=PUT/DELETE in forms and buttons.
import "phoenix_html"
// Establish Phoenix Socket and LiveView configuration.
import {Socket} from "phoenix"
import {LiveSocket} from "phoenix_live_view"
import {hooks as colocatedHooks} from "phoenix-colocated/bbh"
import topbar from "../vendor/topbar"
// Trix rich text editor (self-hosted; registers the <trix-editor> element).
import "../vendor/trix/trix.umd.min.js"
// flatpickr date/time picker (self-hosted; sets window.flatpickr + German locale).
import "../vendor/flatpickr/flatpickr.min.js"
import "../vendor/flatpickr/l10n/de.js"
// Homepage "Nächster Termin" live countdown (progressive enhancement, no LiveView).
import "./countdown.js"

// Sync a Trix editor's content into its hidden input and notify LiveView.
const Hooks = {
  TrixEditor: {
    mounted() {
      const editor = this.el.querySelector("trix-editor")
      const input = this.el.querySelector("input[type=hidden]")
      // No direct uploads — files come from the media library via the picker below.
      editor.addEventListener("trix-file-accept", (e) => e.preventDefault())
      editor.addEventListener("trix-change", () => {
        input.dispatchEvent(new Event("input", {bubbles: true}))
      })

      // Add a "Aus Mediathek…" toolbar button that opens the shared media picker.
      const addButton = () => this.addMediaButton(editor)
      if (editor.toolbarElement) addButton()
      else editor.addEventListener("trix-initialize", addButton, {once: true})

      // The picker (a LiveComponent) pushes the chosen file back to this editor.
      this.handleEvent("media_picker:insert", ({editor: id, html}) => {
        if (id === this.el.id) editor.editor.insertHTML(html)
      })
    },
    addMediaButton(editor) {
      const toolbar = editor.toolbarElement
      const row = toolbar && toolbar.querySelector(".trix-button-row")
      if (!row || row.querySelector(".trix-button--media")) return

      const group = document.createElement("span")
      group.className = "trix-button-group"
      const btn = document.createElement("button")
      btn.type = "button"
      btn.className = "trix-button trix-button--media"
      btn.title = "Aus Mediathek einfügen"
      btn.textContent = "Mediathek"
      btn.addEventListener("click", () =>
        this.pushEventTo("#media-picker", "open", {editor: this.el.id}),
      )
      group.appendChild(btn)
      row.appendChild(group)
    },
  },

  // German-formatted date/time picker. Lives inside a `phx-update="ignore"` wrapper so
  // flatpickr's injected DOM survives LiveView patches; the time picker is toggled off
  // (date only) whenever the linked "ganztägig" checkbox is checked. The real <input>
  // keeps an ISO-ish value LiveView can parse.
  DatePicker: {
    mounted() {
      const sel = this.el.dataset.allDaySelector
      this.checkbox = sel ? document.querySelector(sel) : null
      this._onToggle = () => this.build()
      if (this.checkbox) this.checkbox.addEventListener("change", this._onToggle)
      this.build()
    },
    destroyed() {
      if (this.checkbox) this.checkbox.removeEventListener("change", this._onToggle)
      if (this._fp) this._fp.destroy()
    },
    build() {
      const enableTime = this.checkbox
        ? !this.checkbox.checked
        : this.el.dataset.enableTime === "true"
      if (this._fp) this._fp.destroy()
      this._fp = window.flatpickr(this.el, {
        locale: "de",
        allowInput: true,
        altInput: true,
        time_24hr: true,
        enableTime: enableTime,
        dateFormat: enableTime ? "Y-m-d\\TH:i" : "Y-m-d",
        altFormat: enableTime ? "d.m.Y H:i" : "d.m.Y",
        // Notify LiveView when the bound input changes.
        onChange: () => this.el.dispatchEvent(new Event("input", {bubbles: true})),
      })
    },
  },
}

const csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
const liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: {_csrf_token: csrfToken},
  hooks: {...colocatedHooks, ...Hooks},
})

// Show progress bar on live navigation and form submits
topbar.config({barColors: {0: "#29d"}, shadowColor: "rgba(0, 0, 0, .3)"})
window.addEventListener("phx:page-loading-start", _info => topbar.show(300))
window.addEventListener("phx:page-loading-stop", _info => topbar.hide())

// connect if there are any LiveViews on the page
liveSocket.connect()

// expose liveSocket on window for web console debug logs and latency simulation:
// >> liveSocket.enableDebug()
// >> liveSocket.enableLatencySim(1000)  // enabled for duration of browser session
// >> liveSocket.disableLatencySim()
window.liveSocket = liveSocket

// --- Navigable image lightbox for public galleries (plain JS — no LiveView) ---
// Triggers carry `data-lightbox-src`, `data-lightbox-alt`, and (for galleries)
// `data-lightbox-group="<id>"`. Clicking one opens a native <dialog> and lets the
// visitor move through every image sharing that group via on-screen arrows, keyboard
// (←/→ and h/l, Esc to close), and touch swipe. Delegated so it works on
// server-rendered pages too.
;(function initLightbox() {
  let dialog, imgEl, counterEl, prevBtn, nextBtn
  let group = []
  let index = 0

  function ensureDialog() {
    if (dialog) return dialog
    const style = document.createElement("style")
    style.textContent =
      "dialog.lightbox{padding:0;border:0;background:transparent;width:100vw;height:100vh;max-width:100vw;max-height:100vh;overflow:hidden}" +
      "dialog.lightbox::backdrop{background:rgba(0,0,0,.9)}" +
      "dialog.lightbox .lb-stage{position:relative;width:100vw;height:100vh;display:flex;align-items:center;justify-content:center}" +
      "dialog.lightbox img{max-width:92vw;max-height:92vh;object-fit:contain;border-radius:.5rem}" +
      "dialog.lightbox button{position:absolute;background:rgba(0,0,0,.45);color:#fff;border:0;cursor:pointer;border-radius:9999px;width:3rem;height:3rem;font-size:1.75rem;line-height:1;display:flex;align-items:center;justify-content:center}" +
      "dialog.lightbox button:hover{background:rgba(0,0,0,.75)}" +
      "dialog.lightbox .lb-prev{left:1rem;top:50%;transform:translateY(-50%)}" +
      "dialog.lightbox .lb-next{right:1rem;top:50%;transform:translateY(-50%)}" +
      "dialog.lightbox .lb-close{right:1rem;top:1rem;width:2.5rem;height:2.5rem;font-size:1.25rem}" +
      "dialog.lightbox .lb-counter{position:absolute;bottom:1rem;left:50%;transform:translateX(-50%);color:#fff;background:rgba(0,0,0,.45);padding:.25rem .75rem;border-radius:9999px;font-size:.875rem}"
    document.head.appendChild(style)

    dialog = document.createElement("dialog")
    dialog.className = "lightbox"
    dialog.innerHTML =
      '<div class="lb-stage">' +
      '<button class="lb-close" aria-label="Schließen">✕</button>' +
      '<button class="lb-prev" aria-label="Vorheriges Bild">‹</button>' +
      '<img alt="">' +
      '<button class="lb-next" aria-label="Nächstes Bild">›</button>' +
      '<div class="lb-counter"></div>' +
      "</div>"
    imgEl = dialog.querySelector("img")
    counterEl = dialog.querySelector(".lb-counter")
    prevBtn = dialog.querySelector(".lb-prev")
    nextBtn = dialog.querySelector(".lb-next")

    dialog.querySelector(".lb-close").addEventListener("click", () => dialog.close())
    prevBtn.addEventListener("click", (e) => { e.stopPropagation(); show(index - 1) })
    nextBtn.addEventListener("click", (e) => { e.stopPropagation(); show(index + 1) })
    // Click on the backdrop / empty stage closes; clicking the image does not.
    dialog.addEventListener("click", (e) => {
      if (e.target === dialog || e.target.classList.contains("lb-stage")) dialog.close()
    })

    let startX = null
    dialog.addEventListener("touchstart", (e) => { startX = e.changedTouches[0].clientX }, {passive: true})
    dialog.addEventListener("touchend", (e) => {
      if (startX === null) return
      const dx = e.changedTouches[0].clientX - startX
      if (Math.abs(dx) > 40) show(index + (dx < 0 ? 1 : -1))
      startX = null
    }, {passive: true})

    document.body.appendChild(dialog)
    return dialog
  }

  function show(i) {
    if (!group.length) return
    index = (i + group.length) % group.length
    const t = group[index]
    imgEl.src = t.getAttribute("data-lightbox-src")
    imgEl.alt = t.getAttribute("data-lightbox-alt") || ""
    const multi = group.length > 1
    counterEl.textContent = multi ? `${index + 1} / ${group.length}` : ""
    prevBtn.style.display = nextBtn.style.display = multi ? "flex" : "none"
  }

  document.addEventListener("keydown", (e) => {
    if (!dialog || !dialog.open) return
    if (e.key === "ArrowLeft" || e.key === "h") { e.preventDefault(); show(index - 1) }
    else if (e.key === "ArrowRight" || e.key === "l") { e.preventDefault(); show(index + 1) }
  })

  document.addEventListener("click", (e) => {
    const trigger = e.target.closest("[data-lightbox-src]")
    if (!trigger) return
    e.preventDefault()
    ensureDialog()
    const groupId = trigger.getAttribute("data-lightbox-group")
    group = groupId
      ? Array.from(document.querySelectorAll(`[data-lightbox-group="${CSS.escape(groupId)}"][data-lightbox-src]`))
      : [trigger]
    index = Math.max(0, group.indexOf(trigger))
    show(index)
    dialog.showModal()
  })
})()

// --- Thron-Pager: per <select data-nav-select> zu einem Jahr springen ---
document.addEventListener("change", (e) => {
  const sel = e.target.closest("select[data-nav-select]")
  if (sel && sel.value) location.assign(sel.value)
})

// --- Web Push opt-in (public pages, plain JS — no LiveView required) ---
function urlBase64ToUint8Array(base64String) {
  const padding = "=".repeat((4 - (base64String.length % 4)) % 4)
  const base64 = (base64String + padding).replace(/-/g, "+").replace(/_/g, "/")
  const raw = atob(base64)
  return Uint8Array.from([...raw].map((c) => c.charCodeAt(0)))
}

async function subscribePush(btn) {
  if (!("serviceWorker" in navigator) || !("PushManager" in window)) {
    alert("Push-Benachrichtigungen werden von diesem Browser nicht unterstützt.")
    return
  }
  const key = document.querySelector("meta[name='vapid-public-key']")?.getAttribute("content")
  if (!key) return
  try {
    const reg = await navigator.serviceWorker.register("/sw.js")
    if ((await Notification.requestPermission()) !== "granted") return
    const sub = await reg.pushManager.subscribe({
      userVisibleOnly: true,
      applicationServerKey: urlBase64ToUint8Array(key),
    })
    await fetch("/api/push/subscribe", {
      method: "POST",
      headers: {"content-type": "application/json"},
      body: JSON.stringify({...sub.toJSON(), categories: ["termine", "news"]}),
    })
    if (btn) { btn.textContent = "Benachrichtigungen aktiv ✓"; btn.disabled = true }
  } catch (e) {
    console.error("Push subscription failed", e)
  }
}

const pushBtn = document.getElementById("push-optin")
if (pushBtn) pushBtn.addEventListener("click", () => subscribePush(pushBtn))

// The lines below enable quality of life phoenix_live_reload
// development features:
//
//     1. stream server logs to the browser console
//     2. click on elements to jump to their definitions in your code editor
//
if (process.env.NODE_ENV === "development") {
  window.addEventListener("phx:live_reload:attached", ({detail: reloader}) => {
    // Enable server log streaming to client.
    // Disable with reloader.disableServerLogs()
    reloader.enableServerLogs()

    // Open configured PLUG_EDITOR at file:line of the clicked element's HEEx component
    //
    //   * click with "c" key pressed to open at caller location
    //   * click with "d" key pressed to open at function component definition location
    let keyDown
    window.addEventListener("keydown", e => keyDown = e.key)
    window.addEventListener("keyup", _e => keyDown = null)
    window.addEventListener("click", e => {
      if(keyDown === "c"){
        e.preventDefault()
        e.stopImmediatePropagation()
        reloader.openEditorAtCaller(e.target)
      } else if(keyDown === "d"){
        e.preventDefault()
        e.stopImmediatePropagation()
        reloader.openEditorAtDef(e.target)
      }
    }, true)

    window.liveReloader = reloader
  })
}

