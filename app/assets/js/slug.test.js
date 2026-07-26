// Run with: node --test assets/js/slug.test.js  (no dependencies required)
import {test} from "node:test"
import assert from "node:assert/strict"
import {slugify} from "./slug.js"

test("lowercases and dashes spaces", () => {
  assert.equal(slugify("Sommerfest 2026"), "sommerfest-2026")
})

test("transliterates German umlauts and ß", () => {
  assert.equal(slugify("Schützenfest Grünäü"), "schuetzenfest-gruenaeue")
  assert.equal(slugify("Über die Straße"), "ueber-die-strasse")
})

test("collapses runs of punctuation/whitespace into a single dash", () => {
  assert.equal(slugify("König   &  Königin!!!"), "koenig-koenigin")
})

test("trims leading and trailing dashes", () => {
  assert.equal(slugify("  -- Hallo --  "), "hallo")
})

test("returns empty string for blank or nullish input", () => {
  assert.equal(slugify(""), "")
  assert.equal(slugify(null), "")
  assert.equal(slugify(undefined), "")
  assert.equal(slugify("   "), "")
})

test("drops characters outside the ascii alphanumeric range", () => {
  assert.equal(slugify("Café — Résumé"), "caf-r-sum")
})
