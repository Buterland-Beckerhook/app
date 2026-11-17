// Service worker for Web Push notifications.
self.addEventListener("push", (event) => {
  let data = {};
  try {
    data = event.data ? event.data.json() : {};
  } catch (_e) {
    data = { body: event.data ? event.data.text() : "" };
  }
  const title = data.title || "Buterland-Beckerhook e.V.";
  event.waitUntil(
    self.registration.showNotification(title, {
      body: data.body || "",
      icon: "/images/logo.svg",
      badge: "/images/logo.svg",
      data: { url: data.url || "/" },
    })
  );
});

self.addEventListener("notificationclick", (event) => {
  event.notification.close();
  // Only ever open this site: a payload pointing elsewhere opens the start page instead.
  let url = "/";
  try {
    const target = new URL(event.notification.data.url, self.location.origin);
    if (target.origin === self.location.origin) url = target.href;
  } catch (_e) {}
  event.waitUntil(clients.openWindow(url));
});
