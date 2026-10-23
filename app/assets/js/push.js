// Web Push: opt-in banner, footer link and the settings dialog (public pages,
// plain JS — no LiveView). The browser's own subscription is the source of truth
// for "is this device subscribed"; /api/push/status adds what the server stores
// for it (categories, test receiver), so the state survives a reload.
import {CATEGORIES, pushState, statusText, footerLabel} from "./push_state.js"

const DEFAULT_CATEGORIES = CATEGORIES.map((c) => c.value)

function urlBase64ToUint8Array(base64String) {
  const padding = "=".repeat((4 - (base64String.length % 4)) % 4)
  const base64 = (base64String + padding).replace(/-/g, "+").replace(/_/g, "/")
  const raw = atob(base64)
  return Uint8Array.from([...raw].map((c) => c.charCodeAt(0)))
}

const supported = () => "serviceWorker" in navigator && "PushManager" in window

function iosNeedsInstall() {
  const isIos = /iphone|ipad|ipod/i.test(navigator.userAgent)
  const standalone =
    window.matchMedia("(display-mode: standalone)").matches || window.navigator.standalone === true
  return isIos && !standalone
}

async function postJson(url, body, headers = {}) {
  const res = await fetch(url, {
    method: "POST",
    headers: {"content-type": "application/json", accept: "application/json", ...headers},
    body: JSON.stringify(body),
  })
  if (!res.ok) throw new Error(`${url} answered ${res.status}`)
  return res.json()
}

// The current browser subscription, if any — without prompting for anything.
async function currentSubscription() {
  if (!supported()) return null
  const reg = await navigator.serviceWorker.getRegistration("/")
  return reg ? reg.pushManager.getSubscription() : null
}

// Gather browser + server facts and reduce them to a state (see push_state.js).
async function readState() {
  const facts = {
    supported: supported(),
    iosNeedsInstall: iosNeedsInstall(),
    permission: "Notification" in window ? Notification.permission : "default",
    server: null,
  }
  try {
    const sub = await currentSubscription()
    if (sub) facts.server = await postJson("/api/push/status", {endpoint: sub.endpoint})
  } catch (e) {
    console.error("Push status check failed", e)
  }
  return pushState(facts)
}

// Ask for permission if needed, (re)use the browser subscription and store the
// chosen categories on the server. Returns the subscription, or null if declined.
export async function subscribePush(categories = DEFAULT_CATEGORIES) {
  if (!supported()) return null
  const key = document.querySelector("meta[name='vapid-public-key']")?.getAttribute("content")
  if (!key) return null

  const reg = await navigator.serviceWorker.register("/sw.js")
  if ((await Notification.requestPermission()) !== "granted") return null

  const sub =
    (await reg.pushManager.getSubscription()) ||
    (await reg.pushManager.subscribe({
      userVisibleOnly: true,
      applicationServerKey: urlBase64ToUint8Array(key),
    }))

  await postJson("/api/push/subscribe", {...sub.toJSON(), categories})
  return sub
}

async function unsubscribePush() {
  const sub = await currentSubscription()
  if (!sub) return
  await postJson("/api/push/unsubscribe", {endpoint: sub.endpoint})
  await sub.unsubscribe()
}

// Admin-only: mark this browser as a test receiver (session + CSRF protected).
async function setTester(endpoint, tester) {
  const csrf = document.querySelector("meta[name='csrf-token']")?.getAttribute("content")
  await postJson("/push/tester", {endpoint, tester}, {"x-csrf-token": csrf})
}

// Admin-only: name this browser's subscription so it can be told apart in
// /admin/push (session + CSRF protected, like the tester flag).
async function setLabel(endpoint, label) {
  const csrf = document.querySelector("meta[name='csrf-token']")?.getAttribute("content")
  await postJson("/push/label", {endpoint, label}, {"x-csrf-token": csrf})
}

// LiveView hook for /admin/push: tell the server which row is this browser, so it
// can be marked "Dieses Gerät". The endpoint is only compared, never displayed.
export const PushThisDevice = {
  async mounted() {
    try {
      const sub = await currentSubscription()
      if (sub) this.pushEvent("this_device", {endpoint: sub.endpoint})
    } catch (e) {
      console.error("Push device lookup failed", e)
    }
  },
}

// --- Footer link + settings dialog ---

const footerBtn = document.getElementById("push-optin")
const dialog = document.getElementById("push-dialog")

function render(state) {
  if (footerBtn) footerBtn.textContent = footerLabel(state)
  if (!dialog) return

  dialog.querySelector("#push-status").textContent = statusText(state)

  const actionable = state.kind === "on" || state.kind === "off"
  dialog.querySelector("#push-settings").hidden = !actionable

  const selected = state.kind === "on" ? state.categories : DEFAULT_CATEGORIES
  dialog.querySelectorAll("input[name='push-category']").forEach((box) => {
    box.checked = selected.includes(box.value)
  })

  // The test-receiver switch only exists for admins and needs a subscription.
  const tester = dialog.querySelector("#push-tester")
  if (tester) {
    tester.checked = state.kind === "on" && state.tester
    tester.disabled = state.kind !== "on"
  }

  const label = dialog.querySelector("#push-label")
  if (label) {
    label.value = state.kind === "on" ? state.label : ""
    label.disabled = state.kind !== "on"
  }

  dialog.querySelector("#push-save").textContent = state.kind === "on" ? "Speichern" : "Aktivieren"
  dialog.querySelector("#push-disable").hidden = state.kind !== "on"
}

async function refresh() {
  const state = await readState()
  render(state)
  return state
}

function setBusy(busy) {
  dialog?.querySelectorAll("button").forEach((b) => (b.disabled = busy))
}

async function save() {
  const categories = [...dialog.querySelectorAll("input[name='push-category']:checked")].map(
    (b) => b.value
  )

  // Nothing selected means "no notifications" — the same as turning them off.
  if (categories.length === 0) return unsubscribePush()

  const sub = await subscribePush(categories)
  const tester = dialog.querySelector("#push-tester")
  if (sub && tester && !tester.disabled) await setTester(sub.endpoint, tester.checked)

  const label = dialog.querySelector("#push-label")
  if (sub && label && !label.disabled) await setLabel(sub.endpoint, label.value)
}

if (dialog) {
  footerBtn?.addEventListener("click", async () => {
    dialog.showModal()
    await refresh()
  })

  dialog.querySelector("#push-save").addEventListener("click", async () => {
    setBusy(true)
    try {
      await save()
    } catch (e) {
      console.error("Saving push settings failed", e)
    } finally {
      setBusy(false)
      await refresh()
    }
  })

  dialog.querySelector("#push-disable").addEventListener("click", async () => {
    setBusy(true)
    try {
      await unsubscribePush()
    } catch (e) {
      console.error("Push unsubscribe failed", e)
    } finally {
      setBusy(false)
      await refresh()
    }
  })

  // Once subscribed, the tester switch takes effect immediately.
  dialog.querySelector("#push-tester")?.addEventListener("change", async (e) => {
    const sub = await currentSubscription()
    if (!sub) return
    try {
      await setTester(sub.endpoint, e.target.checked)
    } catch (err) {
      console.error("Setting test receiver failed", err)
    }
    await refresh()
  })

  // Like the tester switch, a name takes effect as soon as the field is left.
  dialog.querySelector("#push-label")?.addEventListener("change", async (e) => {
    const sub = await currentSubscription()
    if (!sub) return
    try {
      await setLabel(sub.endpoint, e.target.value)
    } catch (err) {
      console.error("Naming the device failed", err)
    }
    await refresh()
  })
}

// --- First-visit opt-in banner ---
// The decision (enabled/dismissed) is stored in a cookie so the banner is shown at
// most once; a device that is already subscribed never sees it.

const PUSH_COOKIE = "push_prompt"
const pushCookie = () => document.cookie.split("; ").find((c) => c.startsWith(PUSH_COOKIE + "="))

function rememberPushChoice(value) {
  const oneYear = 60 * 60 * 24 * 365
  document.cookie = `${PUSH_COOKIE}=${value};path=/;max-age=${oneYear};samesite=lax`
}

async function initBanner(state) {
  const banner = document.getElementById("push-banner")
  if (!banner || pushCookie() || state.kind === "on") return

  const enableBtn = document.getElementById("push-banner-enable")
  const dismissBtn = document.getElementById("push-banner-dismiss")

  if (state.kind === "off") {
    enableBtn?.addEventListener("click", async () => {
      try {
        await subscribePush()
      } catch (e) {
        console.error("Push subscription failed", e)
      }
      rememberPushChoice("enabled")
      banner.hidden = true
      await refresh()
    })
    banner.hidden = false
  } else if (state.kind === "install") {
    const text = document.getElementById("push-banner-text")
    if (text) text.textContent = statusText(state)
    enableBtn?.remove()
    banner.hidden = false
  }

  dismissBtn?.addEventListener("click", () => {
    rememberPushChoice("dismissed")
    banner.hidden = true
  })
}

// Show the real state right away (footer link), then decide on the banner.
if (footerBtn || document.getElementById("push-banner")) {
  refresh().then(initBanner)
}
