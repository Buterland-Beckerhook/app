// Run with: node --test assets/js/tag_suggest.test.js  (no dependencies required)
import {test} from "node:test"
import assert from "node:assert/strict"
import {matchTags} from "./tag_suggest.js"

const TAGS = ["Thron", "Kaiserthron", "Biwak", "Jahreshauptversammlung", "Stadtkaiser"]

test("matches case-insensitively, prefix matches first", () => {
  assert.deepEqual(matchTags(TAGS, "thr"), ["Thron", "Kaiserthron"])
  assert.deepEqual(matchTags(TAGS, "KAISER"), ["Kaiserthron", "Stadtkaiser"])
})

test("a blank query lists everything A–Z", () => {
  assert.deepEqual(matchTags(TAGS, "  "), [
    "Biwak",
    "Jahreshauptversammlung",
    "Kaiserthron",
    "Stadtkaiser",
    "Thron",
  ])
})

test("caps the list", () => {
  assert.equal(matchTags(TAGS, "", 2).length, 2)
})

test("no match yields an empty list", () => {
  assert.deepEqual(matchTags(TAGS, "zzz"), [])
})
