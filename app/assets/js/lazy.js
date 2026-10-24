// On-demand loading of the bundles in js/lazy/ (built as extra entry points of the
// `bbh` esbuild profile). The root layout publishes each bundle's digested URL as
// <meta name="bbh-lazy-<name>" content="/assets/js/lazy/<name>.js?vsn=d">, so after a
// deploy a page never fetches a stale copy.
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
    const src = document.querySelector(`meta[name="bbh-lazy-${name}"]`)?.content
    if (!src) return reject(new Error(`no URL for lazy bundle "${name}"`))

    const script = document.createElement("script")
    script.src = src
    if (nonce) script.nonce = nonce
    script.onload = () => resolve()
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
