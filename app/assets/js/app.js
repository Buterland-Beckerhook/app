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
// Quill 2 rich text editor (self-hosted, vendored — no npm). Default import
// unwraps the UMD module.exports (the Quill constructor) via esbuild interop.
import Quill from "../vendor/quill/quill.js"
// flatpickr date/time picker (self-hosted; sets window.flatpickr + German locale).
import "../vendor/flatpickr/flatpickr.min.js"
import "../vendor/flatpickr/l10n/de.js"
// Altcha proof-of-work spam protection (self-hosted; registers <altcha-widget>).
import "../vendor/altcha/altcha.js"
// Homepage "Nächster Termin" live countdown (progressive enhancement, no LiveView).
import "./countdown.js"
// Flash toast auto-hide countdown (plain JS so it works on dead pages too).
import "./flash.js"
// Obfuscated e-mail links -> mailto: on first interaction (see BbhWeb.EmailObfuscation).
import "./mail.js"
// URL slug generation from a title — mirrors Mix.Tasks.Bbh.Import.slugify/1.
import {slugify} from "./slug.js"

// base64url <-> ArrayBuffer helpers for the WebAuthn ceremony (credential ids,
// challenges and signatures cross the wire as pad-less base64url strings).
function b64urlToBuf(value) {
  const pad = "=".repeat((4 - (value.length % 4)) % 4)
  const base64 = (value + pad).replace(/-/g, "+").replace(/_/g, "/")
  return Uint8Array.from(atob(base64), c => c.charCodeAt(0)).buffer
}

function bufToB64url(buffer) {
  let binary = ""
  for (const byte of new Uint8Array(buffer)) binary += String.fromCharCode(byte)
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "")
}

// --- Quill setup: register custom formats once, before any editor mounts. ---
// Default Quill strips class/alt from images; keep them so image size
// (bbh-img-*) and alt text survive editing round-trips.
const QuillImage = Quill.import("formats/image")
const IMG_ATTRS = ["alt", "width", "height", "class"]
class BbhImage extends QuillImage {
  static formats(domNode) {
    return IMG_ATTRS.reduce((formats, attr) => {
      if (domNode.hasAttribute(attr)) formats[attr] = domNode.getAttribute(attr)
      return formats
    }, {})
  }
  format(name, value) {
    if (IMG_ATTRS.includes(name)) {
      if (value) this.domNode.setAttribute(name, value)
      else this.domNode.removeAttribute(name)
    } else {
      super.format(name, value)
    }
  }
}
Quill.register(BbhImage, true)

// Image size as a class attributor -> <img class="bbh-img-md"> etc. Drives the
// "Größe" toolbar dropdown; the server sanitizer whitelists these class tokens.
const Parchment = Quill.import("parchment")
const ImageSize = new Parchment.ClassAttributor("bbhImgSize", "bbh-img", {
  scope: Parchment.Scope.INLINE,
  whitelist: ["sm", "md", "lg", "full"],
})
Quill.register(ImageSize, true)

// Media-library toolbar button icon (Quill-styled 18x18 SVG so it inherits
// hover/active colouring via .ql-stroke / .ql-fill).
const MEDIA_ICON =
  '<svg viewBox="0 0 18 18">' +
  '<rect class="ql-stroke" height="10" width="12" x="3" y="4"></rect>' +
  '<circle class="ql-fill" cx="6" cy="7" r="1"></circle>' +
  '<polyline class="ql-even ql-fill" points="5 12 7 9 9 11 12 7 15 12"></polyline>' +
  "</svg>"

// Sync a Quill editor's content into its hidden input and notify LiveView.
const Hooks = {
  // Auto-fill the slug field from the title while creating content. Bound to the
  // title input; it finds the sibling `[slug]` input in the same form. Generation
  // stays active only while the slug is untouched — an existing value (editing a
  // record) or a manual edit locks it; clearing the slug re-enables auto-fill.
  // The field remains editable at all times.
  SlugFromTitle: {
    mounted() {
      this.slug = this.el.form?.querySelector("input[name$='[slug]']")
      if (!this.slug) return
      this.locked = this.slug.value.trim() !== ""

      this._onTitle = () => {
        if (this.locked) return
        const value = slugify(this.el.value)
        if (this.slug.value === value) return
        this.slug.value = value
        // Serialize the new slug on this same change cycle so LiveView validation
        // (and any re-render) keeps it. Guarded so it doesn't read as a manual edit.
        this._programmatic = true
        this.slug.dispatchEvent(new Event("input", {bubbles: true}))
        this._programmatic = false
      }
      this._onSlug = () => {
        if (!this._programmatic) this.locked = this.slug.value.trim() !== ""
      }

      this.el.addEventListener("input", this._onTitle)
      this.slug.addEventListener("input", this._onSlug)
    },
    destroyed() {
      this.el.removeEventListener("input", this._onTitle)
      if (this.slug) this.slug.removeEventListener("input", this._onSlug)
    },
  },
  // WebAuthn passkeys: runs the credential ceremony synchronously inside the
  // user's gesture. Safari only delegates WebAuthn to a browser-extension
  // credential provider (Bitwarden/1Password) while transient user activation is
  // live; a server round-trip between the click and navigator.credentials would
  // close that window and force Safari's own platform sheet. So the LiveView
  // renders the challenge/options into `data-passkey-options` up front, and the
  // click/submit handler calls navigator.credentials with no round-trip in between.
  Passkey: {
    mounted() {
      this.trigger = this.el.querySelector("[data-passkey-trigger]")
      if (!this.trigger) return
      // A <form> trigger fires on submit (covers the Enter key and carries
      // activation); a button trigger fires on click.
      this.eventName = this.trigger.tagName === "FORM" ? "submit" : "click"
      this._onTrigger = e => this.startCeremony(e)
      this.trigger.addEventListener(this.eventName, this._onTrigger)
    },
    destroyed() {
      if (this.trigger) this.trigger.removeEventListener(this.eventName, this._onTrigger)
    },
    startCeremony(e) {
      e.preventDefault()
      if (this._busy) return
      const opts = JSON.parse(this.el.dataset.passkeyOptions || "null")
      if (!opts) return
      if (this.el.dataset.passkeyCeremony === "create") this.create(opts)
      else this.get(opts)
    },
    async create(opts) {
      // Validate the nickname before touching WebAuthn — a blank name shouldn't
      // open the authenticator UI for nothing.
      const nickname = (this.el.querySelector("input[name='nickname']")?.value || "").trim()
      if (!nickname) {
        this.pushEvent("nickname_blank", {})
        return
      }
      this._busy = true
      try {
        const cred = await navigator.credentials.create({
          publicKey: {
            challenge: b64urlToBuf(opts.challenge),
            rp: opts.rp,
            user: {
              id: b64urlToBuf(opts.user.id),
              name: opts.user.name,
              displayName: opts.user.displayName,
            },
            pubKeyCredParams: [
              {type: "public-key", alg: -7},
              {type: "public-key", alg: -257},
            ],
            authenticatorSelection: {
              residentKey: opts.residentKey,
              userVerification: opts.userVerification,
            },
            excludeCredentials: (opts.excludeCredentials || []).map(id => ({
              type: "public-key",
              id: b64urlToBuf(id),
            })),
            attestation: "none",
          },
        })

        this.pushEvent("register_credential", {
          nickname,
          rawId: bufToB64url(cred.rawId),
          attestationObject: bufToB64url(cred.response.attestationObject),
          clientDataJSON: bufToB64url(cred.response.clientDataJSON),
        })
      } catch (err) {
        this.pushEvent("passkey_error", {message: String(err && err.message ? err.message : err)})
      } finally {
        this._busy = false
      }
    },
    async get(opts) {
      this._busy = true
      try {
        const cred = await navigator.credentials.get({
          publicKey: {
            challenge: b64urlToBuf(opts.challenge),
            rpId: opts.rpId,
            userVerification: opts.userVerification,
            allowCredentials: [],
          },
        })

        this.pushEvent("passkey_login_assertion", {
          rawId: bufToB64url(cred.rawId),
          authenticatorData: bufToB64url(cred.response.authenticatorData),
          clientDataJSON: bufToB64url(cred.response.clientDataJSON),
          signature: bufToB64url(cred.response.signature),
          userHandle: cred.response.userHandle ? bufToB64url(cred.response.userHandle) : null,
        })
      } catch (err) {
        this.pushEvent("passkey_error", {message: String(err && err.message ? err.message : err)})
      } finally {
        this._busy = false
      }
    },
  },
  // Click/drag on the preview image to pick a focal point (0..1 per axis). The
  // fractions drive the crosshair marker and two hidden inputs the media form
  // submits; "Zentrieren" clears them (server treats empty as centered).
  FocalPoint: {
    mounted() {
      this.img = this.el.querySelector("img")
      this.marker = this.el.querySelector("[data-focal-marker]")
      this.xInput = document.getElementById(this.el.dataset.xInput)
      this.yInput = document.getElementById(this.el.dataset.yInput)

      this._onPick = e => this.pick(e)
      this.el.addEventListener("pointerdown", e => {
        this._dragging = true
        this.pick(e)
      })
      this.el.addEventListener("pointermove", e => this._dragging && this.pick(e))
      window.addEventListener("pointerup", (this._stop = () => (this._dragging = false)))

      const reset = this.el.parentElement.querySelector("[data-focal-reset]")
      if (reset) reset.addEventListener("click", (this._onReset = () => this.reset()))
    },
    destroyed() {
      window.removeEventListener("pointerup", this._stop)
    },
    pick(e) {
      const rect = this.img.getBoundingClientRect()
      if (!rect.width || !rect.height) return
      const x = Math.min(1, Math.max(0, (e.clientX - rect.left) / rect.width))
      const y = Math.min(1, Math.max(0, (e.clientY - rect.top) / rect.height))
      this.set(x, y)
    },
    reset() {
      this.set(null, null)
    },
    set(x, y) {
      this.marker.style.left = `${(x ?? 0.5) * 100}%`
      this.marker.style.top = `${(y ?? 0.5) * 100}%`
      this.write(this.xInput, x)
      this.write(this.yInput, y)
    },
    write(input, v) {
      if (!input) return
      input.value = v == null ? "" : v.toFixed(4)
      input.dispatchEvent(new Event("input", {bubbles: true}))
    },
  },
  QuillEditor: {
    mounted() {
      const input = this.el.querySelector("input[type=hidden]")
      const target = this.el.querySelector("[data-quill-editor]")

      const quill = new Quill(target, {
        theme: "snow",
        modules: {
          toolbar: {
            container: [
              [{header: [2, 3, 4, false]}],
              ["bold", "italic", "underline", "strike"],
              [{list: "ordered"}, {list: "bullet"}],
              ["blockquote", "link"],
              [{align: ""}, {align: "center"}, {align: "right"}],
              [{bbhImgSize: ["sm", "md", "lg", "full"]}],
              ["media"],
              ["clean"],
            ],
            handlers: {
              // Files come from the media library — no direct uploads.
              media: () => this.pushEventTo("#media-picker", "open", {editor: this.el.id}),
            },
          },
        },
      })
      this.quill = quill

      // Label the custom media button (Quill renders it empty by default).
      const mediaBtn = quill.getModule("toolbar").container.querySelector("button.ql-media")
      if (mediaBtn) {
        mediaBtn.innerHTML = MEDIA_ICON
        mediaBtn.title = "Aus Mediathek einfügen"
      }

      // Load the stored HTML. Done before wiring text-change so restoring an
      // existing value doesn't mark the form dirty on mount.
      if (input.value) quill.clipboard.dangerouslyPasteHTML(input.value)

      const serialize = () => {
        // getSemanticHTML() yields portable HTML — real <ul>/<ol> lists and
        // class-based alignment (ql-align-*) — unlike root.innerHTML, whose
        // list markers are editor-only CSS. But it escapes *every* space as
        // &nbsp;, which breaks {{ placeholder }} resolution and text wrapping,
        // so restore normal spaces. An empty Quill doc is length 1 (the trailing
        // newline); store "" then.
        input.value =
          quill.getLength() <= 1 ? "" : quill.getSemanticHTML().replaceAll("&nbsp;", " ")
        input.dispatchEvent(new Event("input", {bubbles: true}))
      }
      quill.on("text-change", serialize)

      // The picker (a LiveComponent) pushes the chosen file back to this editor.
      // Every mounted editor receives the event; only the addressed one inserts.
      this.handleEvent("media_picker:insert", ({editor: id, html}) => {
        if (id !== this.el.id) return
        const range = quill.getSelection(true)
        const index = range ? range.index : quill.getLength()
        quill.clipboard.dangerouslyPasteHTML(index, html)
      })
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
// Triggers carry `data-lightbox-src`, `data-lightbox-alt`, optional
// `data-lightbox-caption` / `data-lightbox-copyright`, and (for galleries)
// `data-lightbox-group="<id>"`. Clicking one opens a native <dialog> and lets the
// visitor move through every image sharing that group via on-screen arrows, keyboard
// (←/→ and h/l, Esc to close), and touch swipe. Gallery thumbnails stay bare, so the
// enlarged view is where caption and copyright are shown. Delegated so it works on
// server-rendered pages too.
;(function initLightbox() {
  let dialog, imgEl, barEl, captionEl, counterEl, copyrightEl, prevBtn, nextBtn
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
      // Caption left, counter centered, copyright right — wrapping instead of
      // overlapping when they don't fit side by side.
      "dialog.lightbox .lb-bar{position:absolute;bottom:0;left:0;right:0;display:flex;flex-wrap:wrap;align-items:baseline;justify-content:space-between;gap:.15rem .75rem;padding:.6rem 1rem;color:#fff;font-size:.8125rem;line-height:1.3;background:linear-gradient(to top,rgba(0,0,0,.7),rgba(0,0,0,0))}" +
      // display:flex above would otherwise beat the UA's [hidden] rule.
      "dialog.lightbox .lb-bar[hidden]{display:none}" +
      "dialog.lightbox .lb-caption{min-width:0}" +
      "dialog.lightbox .lb-counter{margin-inline:auto;opacity:.7;white-space:nowrap}" +
      "dialog.lightbox .lb-copyright{margin-left:auto;opacity:.7;white-space:nowrap}"
    document.head.appendChild(style)

    dialog = document.createElement("dialog")
    dialog.className = "lightbox"
    dialog.innerHTML =
      '<div class="lb-stage">' +
      '<button class="lb-close" aria-label="Schließen">✕</button>' +
      '<button class="lb-prev" aria-label="Vorheriges Bild">‹</button>' +
      '<img alt="">' +
      '<button class="lb-next" aria-label="Nächstes Bild">›</button>' +
      '<div class="lb-bar">' +
      '<span class="lb-caption"></span>' +
      '<span class="lb-counter"></span>' +
      '<span class="lb-copyright"></span>' +
      "</div>" +
      "</div>"
    imgEl = dialog.querySelector("img")
    barEl = dialog.querySelector(".lb-bar")
    captionEl = dialog.querySelector(".lb-caption")
    counterEl = dialog.querySelector(".lb-counter")
    copyrightEl = dialog.querySelector(".lb-copyright")
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
    captionEl.textContent = t.getAttribute("data-lightbox-caption") || ""
    copyrightEl.textContent = t.getAttribute("data-lightbox-copyright") || ""
    counterEl.textContent = multi ? `${index + 1} / ${group.length}` : ""
    // No caption, no copyright and a single image — nothing to put in the bar.
    barEl.hidden = !captionEl.textContent && !copyrightEl.textContent && !multi
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

// --- Readonly "zum Kopieren" inputs: click selects all. Delegated so it works on
// dead pages and LiveView-rendered panels alike; an inline onclick would be blocked
// by the CSP (script-src has no 'unsafe-inline'). ---
document.addEventListener("click", (e) => {
  const el = e.target.closest("input[data-select-on-click]")
  if (el) el.select()
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

// First-visit push opt-in banner. The decision (enabled/dismissed) is stored in
// a cookie so the banner is shown at most once until the user clears it.
const PUSH_COOKIE = "push_prompt"
function pushCookie() {
  return document.cookie.split("; ").find((c) => c.startsWith(PUSH_COOKIE + "="))
}
function rememberPushChoice(value) {
  const oneYear = 60 * 60 * 24 * 365
  document.cookie = `${PUSH_COOKIE}=${value};path=/;max-age=${oneYear};samesite=lax`
}

const pushBanner = document.getElementById("push-banner")
if (pushBanner && !pushCookie()) {
  const isStandalone =
    window.matchMedia("(display-mode: standalone)").matches || window.navigator.standalone === true
  const isIos = /iphone|ipad|ipod/i.test(navigator.userAgent)
  const pushSupported = "serviceWorker" in navigator && "PushManager" in window
  const enableBtn = document.getElementById("push-banner-enable")
  const dismissBtn = document.getElementById("push-banner-dismiss")

  if (pushSupported && !(isIos && !isStandalone)) {
    // Push works in this browser — offer to turn it on.
    enableBtn?.addEventListener("click", async () => {
      await subscribePush()
      rememberPushChoice("enabled")
      pushBanner.hidden = true
    })
    pushBanner.hidden = false
  } else if (isIos && !isStandalone) {
    // iOS only delivers push to an installed PWA — show the add-to-home hint.
    const text = document.getElementById("push-banner-text")
    if (text)
      text.textContent =
        'Für Benachrichtigungen: unten im Teilen-Menü „Zum Home-Bildschirm" wählen.'
    enableBtn?.remove()
    pushBanner.hidden = false
  }

  dismissBtn?.addEventListener("click", () => {
    rememberPushChoice("dismissed")
    pushBanner.hidden = true
  })
}

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

