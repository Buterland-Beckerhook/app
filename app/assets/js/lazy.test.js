// Run with: node --test assets/js/lazy.test.js  (no dependencies required)
import {test, beforeEach} from "node:test"
import assert from "node:assert/strict"

// A minimal DOM: just what lazy.js touches. Installed before the module is imported,
// because lazy.js reads document.currentScript at load time.
const appended = []
const metas = {
  "bbh-lazy-editor": "/assets/js/lazy/editor.js?vsn=d",
  "bbh-lazy-flaky": "/assets/js/lazy/flaky.js?vsn=d",
}

globalThis.document = {
  currentScript: {nonce: "abc123"},
  querySelector(selector) {
    const name = selector.match(/^meta\[name="(.+)"\]$/)?.[1]
    return name in metas ? {content: metas[name]} : null
  },
  createElement(tag) {
    return {tag, removed: false, remove() { this.removed = true }}
  },
  head: {append: el => appended.push(el)},
}

const {loadLazy} = await import("./lazy.js")

beforeEach(() => {
  appended.length = 0
})

test("injects one script with the digested URL and the page's nonce", async () => {
  const loading = loadLazy("editor")
  assert.equal(appended.length, 1)
  assert.equal(appended[0].tag, "script")
  assert.equal(appended[0].src, "/assets/js/lazy/editor.js?vsn=d")
  assert.equal(appended[0].nonce, "abc123")

  appended[0].onload()
  await loading
})

test("loads a bundle only once, however often it is asked for", async () => {
  // "editor" was loaded by the previous test.
  await loadLazy("editor")
  await loadLazy("editor")
  assert.equal(appended.length, 0)
})

test("rejects when the layout publishes no URL for the bundle", async () => {
  await assert.rejects(loadLazy("unknown"), /no URL for lazy bundle "unknown"/)
  assert.equal(appended.length, 0)
})

test("a failed load is not cached — the next call tries again", async () => {
  const first = loadLazy("flaky")
  appended[0].onerror()
  await assert.rejects(first, /could not load lazy bundle "flaky"/)
  assert.equal(appended[0].removed, true)

  const second = loadLazy("flaky")
  assert.equal(appended.length, 2)
  appended[1].onload()
  await second
})
