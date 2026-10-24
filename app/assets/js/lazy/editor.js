// The rich-text editor (Quill), loaded on demand by the `QuillEditor` hook in app.js
// — only admin forms have one, so public pages never download it. Built by the same
// esbuild profile as app.js (an extra entry point) and published to the page as
// <meta name="bbh-lazy-editor">; see loadLazy() in lazy.js.
//
// Quill 2 rich text editor (self-hosted, vendored — no npm). Default import
// unwraps the UMD module.exports (the Quill constructor) via esbuild interop.
import Quill from "../../vendor/quill/quill.js"
// Emitted as lazy/editor.css next to this bundle; loadLazy() links it.
import "../../vendor/quill/quill.snow.css"

// --- Quill setup: register custom formats once, before any editor mounts. ---
// Default Quill strips alt from images; keep it (and the dimensions) so they survive
// editing round-trips.
//
// The image formats (size, float, caption line) are class attributors, and Quill
// applies an attributor to an embed by wrapping it in a <span> that carries the class
// — the <img> itself stays bare, so neither the editor CSS nor the server
// (BbhWeb.RichtextImages reads the classes off the <img>) would see it. BbhImage
// therefore claims those formats and sets the class on its own node. Filled in below,
// once the attributors exist.
const QuillImage = Quill.import("formats/image")
const IMG_ATTRS = ["alt", "width", "height"]
const IMAGE_CLASS_FORMATS = {}
class BbhImage extends QuillImage {
  static formats(domNode) {
    const formats = IMG_ATTRS.reduce((formats, attr) => {
      if (domNode.hasAttribute(attr)) formats[attr] = domNode.getAttribute(attr)
      return formats
    }, {})
    for (const [name, attributor] of Object.entries(IMAGE_CLASS_FORMATS)) {
      const value = attributor.value(domNode)
      if (value) formats[name] = value
    }
    return formats
  }
  format(name, value) {
    const attributor = IMAGE_CLASS_FORMATS[name]
    if (attributor) {
      if (value) attributor.add(this.domNode, value)
      else attributor.remove(this.domNode)
      if (!this.domNode.classList.length) this.domNode.removeAttribute("class")
    } else if (IMG_ATTRS.includes(name)) {
      if (value) this.domNode.setAttribute(name, value)
      else this.domNode.removeAttribute(name)
    } else {
      super.format(name, value)
    }
  }
  formatAt(index, length, name, value) {
    if (IMAGE_CLASS_FORMATS[name]) this.format(name, value)
    else super.formatAt(index, length, name, value)
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

// Text wrap around an image -> <img class="bbh-float-right">. Drives the "Umfließen"
// dropdown; same mechanism and server whitelist as ImageSize. The public side reads
// both classes off the wrapper BbhWeb.RichtextImages builds around the image.
const ImageFloat = new Parchment.ClassAttributor("bbhImgFloat", "bbh-float", {
  scope: Parchment.Scope.INLINE,
  whitelist: ["left", "right"],
})
Quill.register(ImageFloat, true)

// What the line under the image shows -> <img class="bbh-cap-copyright">. No class
// means caption and copyright (the default); the texts themselves come from the media
// library at render time (BbhWeb.RichtextImages).
const ImageCaption = new Parchment.ClassAttributor("bbhImgCaption", "bbh-cap", {
  scope: Parchment.Scope.INLINE,
  whitelist: ["none", "caption", "copyright"],
})
Quill.register(ImageCaption, true)

Object.assign(IMAGE_CLASS_FORMATS, {
  bbhImgSize: ImageSize,
  bbhImgFloat: ImageFloat,
  bbhImgCaption: ImageCaption,
})

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

// Sets up one editor for a mounted `QuillEditor` hook (`hook` is the hook instance:
// its element, pushEventTo/handleEvent) and returns the Quill instance.
function mount(hook) {
  const input = hook.el.querySelector("input[type=hidden]")
  const target = hook.el.querySelector("[data-quill-editor]")

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
          [
            {bbhImgSize: ["sm", "md", "lg", "full"]},
            {bbhImgFloat: ["", "left", "right"]},
            {bbhImgCaption: ["", "caption", "copyright", "none"]},
          ],
          ["media"],
          ["clean"],
        ],
        handlers: {
          // Files come from the media library — no direct uploads.
          media: () => hook.pushEventTo("#media-picker", "open", {editor: hook.el.id}),
          // Muted text is a boolean class (bbh-muted); toggle it on the selection.
          bbhMuted: () => {
            const fmt = quill.getFormat()
            quill.format("bbhMuted", fmt.bbhMuted ? false : "on")
          },
        },
      },
    },
  })
  hook.quill = quill

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

  // Tooltips for the image pickers (their German labels come from app.css).
  const pickerTitles = {
    bbhImgSize: "Bildgröße",
    bbhImgFloat: "Bild umfließen",
    bbhImgCaption: "Zeile unter dem Bild",
  }
  for (const [format, title] of Object.entries(pickerTitles)) {
    const label = toolbarEl.querySelector(`.ql-picker.ql-${format} .ql-picker-label`)
    if (label) label.title = title
  }

  // Quill does not select an embed on click, so the image formats above would
  // only apply after Shift+Arrow. Select the clicked image instead.
  quill.root.addEventListener("click", (e) => {
    if (e.target.tagName !== "IMG") return
    const blot = Quill.find(e.target)
    if (blot && blot !== quill) quill.setSelection(quill.getIndex(blot), 1, "user")
  })

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
  hook.handleEvent("media_picker:insert", ({editor: id, html}) => {
    if (id !== hook.el.id) return
    const range = quill.getSelection(true)
    const index = range ? range.index : quill.getLength()
    quill.clipboard.dangerouslyPasteHTML(index, html)
  })

  return quill
}

window.BbhEditor = {mount}
