// On-demand loading of the bundles in js/lazy/ (built as extra entry points of the
// `bbh` esbuild profile). The root layout publishes each bundle's digested URL as
// <meta name="bbh-lazy-<name>" content="/assets/js/lazy/<name>.js?vsn=d">, so after a
// deploy a page never fetches a stale copy. A bundle that imports CSS (esbuild emits it
// as <name>.css next to the script) also carries `data-css` with that URL.
//
// The script element is created from app.js, which carries the CSP nonce: under
// `script-src 'nonce-…' 'strict-dynamic'` a script inserted by a trusted script is
// trusted too. The nonce is copied onto it anyway, for browsers without
// 'strict-dynamic'.

// Read while app.js itself is executing — `document.currentScript` is null later.
const nonce = document.currentScript?.nonce

const pending = {}

export function loadLazy(name) {
  pending[name] ||= new Promise((resolve, reject) => {
    const meta = document.querySelector(`meta[name="bbh-lazy-${name}"]`)
    const src = meta?.content
    if (!src) return reject(new Error(`no URL for lazy bundle "${name}"`))

    // Started alongside the script; the bundle counts as loaded once both are in, so a
    // widget is never built against missing styles.
    const css = meta.dataset?.css
    const styled = css ? linkStylesheet(css) : Promise.resolve()

    const script = document.createElement("script")
    script.src = src
    if (nonce) script.nonce = nonce
    script.onload = () => styled.then(resolve)
    script.onerror = () => {
      // Let a later call retry (a flaky connection) instead of caching the failure.
      delete pending[name]
      script.remove()
      reject(new Error(`could not load lazy bundle "${name}"`))
    }
    document.head.append(script)
  })

  return pending[name]
}

// Insert the stylesheet *before* app.css (#app-css), so the site's own overrides of the
// library's rules keep winning — the order they had when app.css imported them. Never
// rejects: an unstyled widget is still better than none.
function linkStylesheet(href) {
  if (document.querySelector(`link[rel="stylesheet"][href="${href}"]`)) return Promise.resolve()

  return new Promise(resolve => {
    const link = document.createElement("link")
    link.rel = "stylesheet"
    link.href = href
    link.onload = link.onerror = () => resolve()

    const appCss = document.getElementById("app-css")
    if (appCss) appCss.before(link)
    else document.head.append(link)
  })
}
