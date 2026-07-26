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

// Grows the membership form's "Kinder unter 15 Jahren" rows on demand.
import "./membership.js"
// Gallery block in "Diashow" layout: index arithmetic for the controller further down.
import {step, nearestSlide} from "./slideshow.js"
// URL slug generation from a title — mirrors Mix.Tasks.Bbh.Import.slugify/1.
import {slugify} from "./slug.js"
// Drop-target geometry and payload types for the admin media folder tree.
import {dropIntent, FOLDER_TYPE, MEDIA_TYPE} from "./tree_dnd.js"

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

// Font weight, text size and "muted" text as inline class attributors -> spans
// like <span class="bbh-weight-500">. Same mechanism as image size; the server
// sanitizer whitelists these class tokens (bbh-weight-*, bbh-size-*, bbh-muted).
const TextWeight = new Parchment.ClassAttributor("bbhWeight", "bbh-weight", {
  scope: Parchment.Scope.INLINE,
  whitelist: ["100", "200", "300", "400", "500", "600", "700", "800", "900"],
})
Quill.register(TextWeight, true)

const TextSize = new Parchment.ClassAttributor("bbhTextSize", "bbh-size", {
  scope: Parchment.Scope.INLINE,
  whitelist: ["xs", "sm", "lg", "xl", "2xl"],
})
Quill.register(TextSize, true)

const MutedText = new Parchment.ClassAttributor("bbhMuted", "bbh-muted", {
  scope: Parchment.Scope.INLINE,
  whitelist: ["on"],
})
Quill.register(MutedText, true)

// Media-library toolbar button icon (Quill-styled 18x18 SVG so it inherits
// hover/active colouring via .ql-stroke / .ql-fill).
const MEDIA_ICON =
  '<svg viewBox="0 0 18 18">' +
  '<rect class="ql-stroke" height="10" width="12" x="3" y="4"></rect>' +
  '<circle class="ql-fill" cx="6" cy="7" r="1"></circle>' +
  '<polyline class="ql-even ql-fill" points="5 12 7 9 9 11 12 7 15 12"></polyline>' +
  "</svg>"

// Muted-text toolbar button icon: an "A" with a half-filled contrast disc, hinting
// at a dimmed text colour. Quill-styled so it inherits hover/active colouring.
const MUTED_ICON =
  '<svg viewBox="0 0 18 18">' +
  '<path class="ql-fill" d="M9 3a6 6 0 0 0 0 12V3z"></path>' +
  '<circle class="ql-stroke" cx="9" cy="9" r="6"></circle>' +
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
              [
                {header: [1, 2, 3, 4, false]},
                {bbhWeight: ["100", "200", "300", "400", "500", "600", "700", "800", "900"]},
              ],
              ["bold", "italic", "underline", "strike", "bbhMuted"],
              [{bbhTextSize: ["xs", "sm", "", "lg", "xl", "2xl"]}],
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
              // Muted text is a boolean class (bbh-muted); toggle it on the selection.
              bbhMuted: () => {
                const fmt = quill.getFormat()
                quill.format("bbhMuted", fmt.bbhMuted ? false : "on")
              },
            },
          },
        },
      })
      this.quill = quill

      // Label the custom media button (Quill renders it empty by default).
      const toolbarEl = quill.getModule("toolbar").container
      const mediaBtn = toolbarEl.querySelector("button.ql-media")
      if (mediaBtn) {
        mediaBtn.innerHTML = MEDIA_ICON
        mediaBtn.title = "Aus Mediathek einfügen"
      }

      // Label the custom muted-text toggle (also renders empty by default).
      const mutedBtn = toolbarEl.querySelector("button.ql-bbhMuted")
      if (mutedBtn) {
        mutedBtn.innerHTML = MUTED_ICON
        mutedBtn.title = "Gedämpfter Text"
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

  // Drag & drop in the admin media folder tree: reorder folders among their siblings,
  // nest one folder inside another, and drop media tiles onto a folder to file them.
  //
  // Every listener is delegated from the tree container. That is not a style choice —
  // LiveView replaces the rows on each re-render, so listeners bound to individual rows
  // would be dead after the first move. The container itself keeps its identity.
  //
  // The hook only draws the affordance and reports the move. Which moves are legal is
  // decided server-side (Bbh.Media.Folder.move_changeset/4); the one rule mirrored here
  // is the two-level cap, so an impossible nest is never offered in the first place
  // rather than being flashed as an error after the drop.
  //
  // Moving a folder needs "Ordner sortieren" on. For drags that needs no check: start()
  // begins at [data-drag-handle], and the grip is only rendered in that mode. The keys
  // hang off the row's link instead, which is always there, so key() checks explicitly.
  // Filing a media tile works in either mode — it never touches a grip.
  MediaTree: {
    mounted() {
      this._listeners = {
        dragstart: e => this.start(e),
        dragover: e => this.over(e),
        dragleave: e => this.leave(e),
        drop: e => this.drop(e),
        dragend: () => this.reset(),
        keydown: e => this.key(e),
      }

      for (const [name, fn] of Object.entries(this._listeners)) {
        this.el.addEventListener(name, fn)
      }
    },
    destroyed() {
      for (const [name, fn] of Object.entries(this._listeners || {})) {
        this.el.removeEventListener(name, fn)
      }
    },

    start(e) {
      const row = e.target.closest("[data-drag-handle]")?.closest("[data-node]")
      if (!row?.dataset.folderId) return

      // Everything about the dragged folder is stashed as plain values, never as the
      // node: a LiveView patch mid-drag (a flash dismissing, another admin's change)
      // detaches `row`, and node-identity comparisons would then quietly stop matching —
      // letting a folder be dropped on itself and skipping the index correction below.
      this.draggingId = row.dataset.folderId
      this.draggingLeaf = row.dataset.leaf === "true"
      this.draggingParentId = row.dataset.parentId

      e.dataTransfer.effectAllowed = "move"
      e.dataTransfer.setData(FOLDER_TYPE, row.dataset.folderId)
      // Firefox will not start a drag at all unless text/plain is set.
      e.dataTransfer.setData("text/plain", row.dataset.folderId)
      // Without this the drag ghost is just the grip icon.
      e.dataTransfer.setDragImage(row, 0, 0)
    },

    over(e) {
      const target = this.resolveTarget(e)
      if (!target) return

      e.preventDefault()
      e.dataTransfer.dropEffect = "move"
      this.clearMarkers()
      target.row.dataset.drop = target.intent
    },

    leave(e) {
      const row = e.target.closest?.("[data-node]")
      // dragleave also fires when the pointer crosses into a child of the same row.
      if (row && !row.contains(e.relatedTarget)) delete row.dataset.drop
    },

    drop(e) {
      // Read the dragged folder out of hook state up front. destination() needs it, and
      // resetting first would silently drop the same-level index adjustment below —
      // the folder would then land one slot too low on every downward drag.
      const dragging = this.draggingId
      const target = this.resolveTarget(e)
      this.reset()
      if (!target) return
      e.preventDefault()

      if (target.kind === "media") {
        const id = e.dataTransfer.getData(MEDIA_TYPE)
        // A row with no folder id is "Ohne Ordner" — an empty string unfiles the item.
        if (id) this.pushEvent("move_media", {id, folder_id: target.row.dataset.folderId || ""})
        return
      }

      const id = e.dataTransfer.getData(FOLDER_TYPE)
      if (id) this.pushEvent("move_folder", {id, ...this.destination(target, dragging)})
    },

    // The row under the pointer, what is being dragged, and where it would land — or
    // null when this is not a target at all (wrong payload, own row, view-only node,
    // or a move the two-level cap forbids). Reads the dragged folder from hook state;
    // both callers run before reset(), so there is nothing to thread through.
    resolveTarget(e) {
      const row = e.target.closest?.("[data-node]")
      if (!row) return null

      const types = e.dataTransfer.types
      const kind = types.includes(FOLDER_TYPE)
        ? "folder"
        : types.includes(MEDIA_TYPE)
          ? "media"
          : null

      if (!kind) return null
      if (!(row.dataset.accepts || "").split(" ").includes(kind)) return null
      if (kind === "media") return {row, kind, intent: "into"}
      if (row.dataset.folderId === this.draggingId) return null

      // A folder that has sub-folders can never change level — only reorder among its
      // own siblings. Refusing the whole row (not just the "into" third) is what makes
      // the affordance honest: dropping between two sub-folders would otherwise draw an
      // insertion line and then be rejected by the server, because landing there means
      // taking their parent.
      if (!this.draggingLeaf && row.dataset.parentId !== this.draggingParentId) return null

      // Nesting additionally needs a top-level target: one level down is the limit.
      const allowInto = row.dataset.parentId === "" && this.draggingLeaf

      return {row, kind, intent: dropIntent(row.getBoundingClientRect(), e.clientY, {allowInto})}
    },

    // Translate a drop into the {parent_id, position} the server expects.
    destination({row, intent}, draggingId) {
      if (intent === "into") {
        const parentId = row.dataset.folderId
        return {parent_id: parentId, position: this.siblings(parentId).length}
      }

      const parentId = row.dataset.parentId
      const siblings = this.siblings(parentId)
      let position = siblings.indexOf(row) + (intent === "after" ? 1 : 0)

      // The server takes the moved folder out of the level before inserting it, so an
      // index counted while it is still in place sits one too high.
      const from = siblings.findIndex(s => s.dataset.folderId === draggingId)
      if (from !== -1 && from < position) position -= 1

      return {parent_id: parentId, position}
    },

    // Folder rows on one level, in the order they are rendered.
    siblings(parentId) {
      const selector = `[data-node][data-folder-id][data-parent-id="${parentId ?? ""}"]`
      return [...this.el.querySelectorAll(selector)]
    },

    // Keyboard equivalent of the two drag gestures, so the tree is not drag-only:
    // Alt+Up/Down reorders among siblings, Alt+Right nests under the row above,
    // Alt+Left lifts a sub-folder back to the top level.
    key(e) {
      if (!e.altKey) return
      // Only while sorting is on. Not merely to match the grips: outside that mode folded
      // branches sit on `hidden`, and siblings() counts them all the same — a position
      // worked out against a half-invisible level is not the one the editor is looking at.
      // Read per event, so it follows every render without an updated() hook.
      if (this.el.dataset.editMode !== "true") return
      if (!["ArrowUp", "ArrowDown", "ArrowLeft", "ArrowRight"].includes(e.key)) return

      const row = e.target.closest?.("[data-tree-link]")?.closest("[data-node]")
      if (!row?.dataset.folderId) return

      // Swallow the key whether or not the move is possible. Alt+Left/Right are the
      // browser's Back/Forward: returning early on a refused move would turn "this
      // folder cannot be unnested" into "leave the page".
      e.preventDefault()

      const destination = this.keyDestination(e.key, row)
      if (destination) this.pushEvent("move_folder", {id: row.dataset.folderId, ...destination})
    },

    keyDestination(key, row) {
      const parentId = row.dataset.parentId
      const siblings = this.siblings(parentId)
      const index = siblings.indexOf(row)

      switch (key) {
        case "ArrowUp":
          return index > 0 ? {parent_id: parentId, position: index - 1} : null

        case "ArrowDown":
          return index < siblings.length - 1 ? {parent_id: parentId, position: index + 1} : null

        case "ArrowRight": {
          const previous = siblings[index - 1]
          if (parentId !== "" || !previous || row.dataset.leaf !== "true") return null
          const target = previous.dataset.folderId
          return {parent_id: target, position: this.siblings(target).length}
        }

        case "ArrowLeft": {
          if (!parentId) return null
          const roots = this.siblings("")
          const parentRow = roots.find(r => r.dataset.folderId === parentId)
          // Land directly below the folder it came out of, not at the bottom.
          return {parent_id: "", position: roots.indexOf(parentRow) + 1}
        }

        default:
          return null
      }
    },

    reset() {
      this.draggingId = null
      this.draggingLeaf = false
      this.draggingParentId = null
      this.clearMarkers()
    },

    clearMarkers() {
      this.el.querySelectorAll("[data-drop]").forEach(el => delete el.dataset.drop)
    },
  },

  // Drag source for the media grid. Separate from MediaTree because the grid is a
  // LiveView stream: the container survives patches, its tiles do not, so the listener
  // has to be delegated from here rather than bound per tile.
  MediaGrid: {
    mounted() {
      this._onDragStart = e => {
        const tile = e.target.closest("[data-media-id]")
        if (!tile) return

        e.dataTransfer.effectAllowed = "move"
        e.dataTransfer.setData(MEDIA_TYPE, tile.dataset.mediaId)
        e.dataTransfer.setData("text/plain", tile.dataset.mediaId)
      }

      this.el.addEventListener("dragstart", this._onDragStart)
    },
    destroyed() {
      this.el.removeEventListener("dragstart", this._onDragStart)
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
  let dialog, imgEl, captionEl, counterEl, copyrightEl, prevBtn, nextBtn
  let group = []
  let index = 0

  function ensureDialog() {
    if (dialog) return dialog
    const muted = "rgba(255,255,255,.55)"
    const style = document.createElement("style")
    style.textContent =
      "dialog.lightbox{padding:0;border:0;background:transparent;width:100vw;height:100vh;max-width:100vw;max-height:100vh;overflow:hidden}" +
      "dialog.lightbox::backdrop{background:rgba(0,0,0,.92)}" +
      "dialog.lightbox .lb-stage{position:relative;width:100vw;height:100vh;display:flex;align-items:center;justify-content:center}" +
      // Image + caption stack, centred and shrink-wrapped so the caption's left
      // edge lines up with the image's left edge.
      "dialog.lightbox .lb-figure{margin:auto;display:flex;flex-direction:column;max-width:92vw;max-height:92vh}" +
      "dialog.lightbox img{max-width:100%;max-height:86vh;object-fit:contain;border-radius:.25rem}" +
      // Caption sits directly under the image, left-aligned.
      "dialog.lightbox .lb-caption{margin-top:.5rem;color:rgba(255,255,255,.8);font-size:.8125rem;line-height:1.3;text-align:left}" +
      "dialog.lightbox .lb-caption[hidden]{display:none}" +
      // Minimal, background-less controls: muted glyphs that brighten on hover. Extra
      // inset keeps them clear of the window edge (and any scrollbar behind the modal).
      "dialog.lightbox button{position:absolute;background:none;border:0;padding:0;cursor:pointer;color:" + muted + ";line-height:1;transition:color .15s,opacity .15s}" +
      "dialog.lightbox button:hover{color:#fff}" +
      // Chevrons: tall (2× via scaleY) and darker, with a drop-shadow so they read over
      // the image itself — like the gallery slideshow arrows.
      "dialog.lightbox .lb-prev,dialog.lightbox .lb-next{top:50%;transform:translateY(-50%) scaleY(2);font-size:2.75rem;color:rgba(170,170,170,.7);text-shadow:0 2px 8px rgba(0,0,0,.75)}" +
      "dialog.lightbox .lb-prev{left:2rem}" +
      "dialog.lightbox .lb-next{right:2rem}" +
      "dialog.lightbox .lb-close{top:1.25rem;right:2rem;font-size:2rem;text-shadow:0 2px 8px rgba(0,0,0,.75)}" +
      // Counter centred at the bottom of the window, copyright pinned bottom-right.
      "dialog.lightbox .lb-counter{position:absolute;bottom:.6rem;left:50%;transform:translateX(-50%);color:" + muted + ";font-size:.8125rem;white-space:nowrap}" +
      "dialog.lightbox .lb-counter[hidden]{display:none}" +
      "dialog.lightbox .lb-copyright{position:absolute;bottom:.6rem;right:1.25rem;color:" + muted + ";font-size:.8125rem;white-space:nowrap}" +
      "dialog.lightbox .lb-copyright[hidden]{display:none}"
    document.head.appendChild(style)

    dialog = document.createElement("dialog")
    dialog.className = "lightbox"
    dialog.innerHTML =
      '<div class="lb-stage">' +
      '<button class="lb-close" aria-label="Schließen">✕</button>' +
      '<button class="lb-prev" aria-label="Vorheriges Bild">‹</button>' +
      '<figure class="lb-figure">' +
      '<img alt="">' +
      '<figcaption class="lb-caption"></figcaption>' +
      "</figure>" +
      '<button class="lb-next" aria-label="Nächstes Bild">›</button>' +
      '<div class="lb-counter"></div>' +
      '<div class="lb-copyright"></div>' +
      "</div>"
    imgEl = dialog.querySelector("img")
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
    captionEl.hidden = !captionEl.textContent
    copyrightEl.hidden = !copyrightEl.textContent
    counterEl.hidden = !multi
    prevBtn.style.display = nextBtn.style.display = multi ? "block" : "none"
  }

  document.addEventListener("keydown", (e) => {
    if (!dialog || !dialog.open) return
    if (e.key === "ArrowLeft" || e.key === "h") { e.preventDefault(); show(index - 1) }
    else if (e.key === "ArrowRight" || e.key === "l") { e.preventDefault(); show(index + 1) }
  })

  // Open the lightbox at `trigger`, pulling in every element that shares its group.
  function openLightbox(trigger) {
    if (!trigger) return
    ensureDialog()
    const groupId = trigger.getAttribute("data-lightbox-group")
    group = groupId
      ? Array.from(document.querySelectorAll(`[data-lightbox-group="${CSS.escape(groupId)}"][data-lightbox-src]`))
      : [trigger]
    index = Math.max(0, group.indexOf(trigger))
    show(index)
    dialog.showModal()
  }
  // Every trigger is handled here, slideshow slides included: a slide's picture is a
  // real button, so there is no pointer-position guessing for this to stay out of.
  document.addEventListener("click", (e) => {
    const trigger = e.target.closest("[data-lightbox-src]")
    if (!trigger) return
    e.preventDefault()
    openLightbox(trigger)
  })
})()

// --- Gallery block, "Diashow" layout (BbhWeb.SiteComponents.gallery_slideshow) ---
// The strip is a CSS scroll-snap container, so swiping, snapping and the push animation
// come from the browser and work with this switched off. Added here is only what a
// scroll container has no opinion about: arrows, dots and advancing on a timer. The
// index arithmetic lives in slideshow.js, where it is unit-tested.
;(function initSlideshows() {
  const motionQuery = window.matchMedia("(prefers-reduced-motion: reduce)")

  function setup(root) {
    const track = root.querySelector("[data-slideshow-track]")
    if (!track) return

    const slides = Array.from(track.children)
    const dots = Array.from(root.querySelectorAll("[data-slideshow-dot]"))
    if (slides.length < 2) return

    const slideWidth = () => slides[0].getBoundingClientRect().width

    // Where a smooth scroll started here is heading, for as long as it is in flight.
    // The scroll position is still the source of truth for anything the visitor drives
    // — but a scroll *this code* started has not arrived yet, and reading the strip
    // mid-animation would answer with the slide being scrolled away from. Two quick
    // clicks on the arrow would then both be answered "you are on slide 1" and the
    // second would go nowhere. Cleared once the strip stops moving, so a swipe, a
    // trackpad flick and a resize all go back to being read off the position.
    let heading = null
    // The last slide the strip came to rest on. Only used to put it back after a
    // resize — see the resize listener.
    let settled = 0
    const current = () =>
      heading === null ? nearestSlide(track.scrollLeft, slideWidth(), slides.length) : heading

    let headingTimer = null

    // `behavior` is left off on purpose: its default, "auto", means "use the element's
    // computed scroll-behavior", and app.css sets that to smooth — including flipping
    // it back under prefers-reduced-motion. One place decides how this animates.
    // "instant" is passed only where the animation itself is wrong.
    function goTo(index, {instant = false} = {}) {
      heading = index
      const left = index * slideWidth()
      track.scrollTo(instant ? {left, behavior: "instant"} : {left})

      // A scrollTo to where the strip already is fires no scroll event, so the settle
      // timer below would never run and `heading` would stick. Reachable by clicking
      // the current slide's own dot.
      window.clearTimeout(headingTimer)
      headingTimer = window.setTimeout(() => {
        if (heading === index) heading = null
      }, 800)
    }

    // One step to a neighbour animates; wrapping round the end does not. A wrap is a
    // scroll across the whole strip, and smooth-scrolling it drags the reader past every
    // picture in between — a rewind on a three-image gallery, seconds of strobing on a
    // twenty-image one, and under autoplay it would happen every cycle.
    function advance(delta) {
      const from = current()
      const to = step(from, delta, slides.length)
      goTo(to, {instant: Math.abs(to - from) > 1})
    }

    // --- Autoplay ---
    // Absent unless the editor asked for it, and refused outright to a reader who asked
    // for reduced motion — a picture that moves on its own is what that setting is about.
    const interval = Number(root.dataset.slideshowInterval)
    const autoplays = interval > 0 && !motionQuery.matches
    let timer = null
    let takenOver = false

    function pause() {
      if (timer !== null) window.clearInterval(timer)
      timer = null
    }

    function resume() {
      if (timer !== null || takenOver || !autoplays) return
      timer = window.setInterval(() => {
        // A background tab would otherwise queue up scrolls nobody is watching and land
        // on an arbitrary slide once the reader comes back.
        if (document.hidden) return
        advance(1)
      }, interval)
    }

    // Any deliberate move by the visitor stops the show for good — an arrow, a dot, or
    // a swipe. That is both the polite reading (they are browsing at their own pace
    // now) and how an autoplaying Diashow here satisfies WCAG 2.2.2: it always carries
    // a control that halts the motion.
    //
    // The swipe case is the one that matters. Hover-pause is a desktop affordance; on
    // touch, `pointerenter`/`pointerleave` fire at the start and end of the swipe
    // itself, so without this the timer restarts the moment a finger lifts and moves
    // the reader off the picture they just swiped to.
    function takeOver() {
      takenOver = true
      pause()
    }

    root.querySelector("[data-slideshow-prev]")?.addEventListener("click", () => {
      takeOver()
      advance(-1)
    })

    root.querySelector("[data-slideshow-next]")?.addEventListener("click", () => {
      takeOver()
      advance(1)
    })

    dots.forEach((dot) => {
      dot.addEventListener("click", () => {
        takeOver()
        goTo(Number(dot.dataset.slideshowDot))
      })
    })

    // Coalesced to one read per frame: a smooth scroll fires this dozens of times.
    let queued = false
    function syncDots() {
      if (queued) return
      queued = true
      window.requestAnimationFrame(() => {
        queued = false
        const active = current()
        dots.forEach((dot, i) => dot.setAttribute("aria-current", String(i === active)))
      })
    }

    // `scrollend` would say this outright, but Safari only learned it recently, and
    // this is the same thing every polyfill does: the strip has stopped when it has
    // been quiet for a couple of frames.
    let settleTimer = null
    track.addEventListener(
      "scroll",
      () => {
        syncDots()
        window.clearTimeout(settleTimer)
        settleTimer = window.setTimeout(() => {
          // No `heading` means nothing here started this scroll — the visitor did, by
          // swiping or flicking. Same contract as pressing an arrow.
          if (heading === null) takeOver()
          heading = null
          settled = nearestSlide(track.scrollLeft, slideWidth(), slides.length)
          syncDots()
        }, 150)
      },
      {passive: true},
    )

    // Put the strip back on the slide that was showing. A resize changes how wide a
    // slide is, and the browser answers that by re-snapping to the start — so without
    // this, turning a phone sideways sends the reader back to picture one. Instant on
    // purpose: this is restoring a position, not travelling to a new one, and `heading`
    // is set with it so the settle above does not read the restore as a swipe.
    //
    // Observing the track rather than the window: a slide is as wide as its container,
    // so width is the only thing that can invalidate the position — and this also
    // catches a zoom change or a page scrollbar appearing, which `window.innerWidth`
    // misses. It ignores the height-only resize that hiding a mobile address bar
    // fires mid-scroll, which would otherwise snatch the strip from a moving finger.
    let lastWidth = null
    new ResizeObserver(([entry]) => {
      const width = Math.round(entry.contentRect.width)
      if (width === lastWidth) return
      const first = lastWidth === null
      lastWidth = width
      if (first || !width) return
      goTo(settled, {instant: true})
      syncDots()
    }).observe(track)

    if (autoplays) {
      // Pause while it is being read or reached for: hover and keyboard focus.
      root.addEventListener("pointerenter", pause)
      root.addEventListener("pointerleave", resume)
      root.addEventListener("focusin", pause)
      root.addEventListener("focusout", (e) => {
        if (!root.contains(e.relatedTarget)) resume()
      })
      resume()
    }
  }

  const start = () => document.querySelectorAll("[data-slideshow]").forEach(setup)
  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", start)
  } else {
    start()
  }
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

