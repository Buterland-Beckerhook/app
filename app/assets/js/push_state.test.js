// Run with: node --test assets/js/push_state.test.js  (no dependencies required)
import {test} from "node:test"
import assert from "node:assert/strict"
import {pushState, statusText, footerLabel} from "./push_state.js"

const base = {supported: true, iosNeedsInstall: false, permission: "default", server: null}

test("no browser subscription is off", () => {
  assert.deepEqual(pushState(base), {kind: "off"})
})

test("a subscription the server knows is on, with its categories", () => {
  const state = pushState({
    ...base,
    permission: "granted",
    server: {subscribed: true, categories: ["news"], tester: true},
  })

  assert.deepEqual(state, {kind: "on", categories: ["news"], tester: true})
  assert.equal(statusText(state), "Aktiv auf diesem Gerät für: Neue Beiträge.")
  assert.equal(footerLabel(state), "Benachrichtigungen: aktiv")
})

test("a subscription the server dropped (or with no categories) is off", () => {
  assert.equal(pushState({...base, server: {subscribed: false}}).kind, "off")

  assert.equal(
    pushState({...base, server: {subscribed: true, categories: [], tester: false}}).kind,
    "off"
  )
})

test("blocked permission wins over a stale subscription", () => {
  const state = pushState({
    ...base,
    permission: "denied",
    server: {subscribed: true, categories: ["termine"]},
  })

  assert.equal(state.kind, "denied")
})

test("iOS outside an installed web app needs installing first", () => {
  assert.equal(pushState({...base, supported: false, iosNeedsInstall: true}).kind, "install")
})

test("no Push API is unsupported", () => {
  assert.equal(pushState({...base, supported: false}).kind, "unsupported")
  assert.equal(footerLabel({kind: "unsupported"}), "Benachrichtigungen")
})
