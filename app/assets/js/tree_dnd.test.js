// Run with: node --test assets/js/tree_dnd.test.js  (no dependencies required)
import {test} from "node:test"
import assert from "node:assert/strict"
import {dropIntent, FOLDER_TYPE, MEDIA_TYPE} from "./tree_dnd.js"

// A 20px-tall row starting at y=100: quarters at 105 and 115.
const row = {top: 100, height: 20}

test("the top quarter files the folder above the row", () => {
  assert.equal(dropIntent(row, 100), "before")
  assert.equal(dropIntent(row, 104), "before")
})

test("the bottom quarter files the folder below the row", () => {
  assert.equal(dropIntent(row, 116), "after")
  assert.equal(dropIntent(row, 120), "after")
})

test("the middle half nests the folder inside the row", () => {
  assert.equal(dropIntent(row, 105), "into")
  assert.equal(dropIntent(row, 110), "into")
  assert.equal(dropIntent(row, 115), "into")
})

test("the quarter boundaries belong to 'into', not to the edges", () => {
  // Exactly on 25%/75%: neither `<` nor `>` fires, so the middle wins. Pinned because
  // an off-by-one here would make the nesting zone silently smaller than half the row.
  assert.equal(dropIntent({top: 0, height: 100}, 25), "into")
  assert.equal(dropIntent({top: 0, height: 100}, 75), "into")
})

test("without nesting the row splits in half — no dead zone", () => {
  const opts = {allowInto: false}

  assert.equal(dropIntent(row, 100, opts), "before")
  assert.equal(dropIntent(row, 109, opts), "before")
  assert.equal(dropIntent(row, 110, opts), "after")
  assert.equal(dropIntent(row, 120, opts), "after")
})

test("a pointer past the row still resolves to the nearest edge", () => {
  // dragover can fire with coordinates slightly outside the rect (sub-pixel layout,
  // fast pointer). It must never fall through to "into" by accident.
  assert.equal(dropIntent(row, 40), "before")
  assert.equal(dropIntent(row, 400), "after")
  assert.equal(dropIntent(row, 40, {allowInto: false}), "before")
  assert.equal(dropIntent(row, 400, {allowInto: false}), "after")
})

test("a row with no layout has no geometry to divide", () => {
  // Mid-patch or display:none — every offset would otherwise land in "before".
  assert.equal(dropIntent({top: 0, height: 0}, 0), "into")
  assert.equal(dropIntent({top: 0, height: 0}, 0, {allowInto: false}), "before")
})

test("payload types are distinct and namespaced", () => {
  // The tree tells a folder drag from a media drag by MIME type alone, because
  // dataTransfer values are unreadable during dragover.
  assert.notEqual(FOLDER_TYPE, MEDIA_TYPE)
  assert.match(FOLDER_TYPE, /^application\/x-bbh-/)
  assert.match(MEDIA_TYPE, /^application\/x-bbh-/)
})
