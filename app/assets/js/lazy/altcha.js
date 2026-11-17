// Altcha proof-of-work spam protection (self-hosted), loaded on demand by app.js on
// pages that render an <altcha-widget> (contact and membership forms). Importing it
// registers the custom element; widgets already in the page upgrade at that moment.
import "../../vendor/altcha/altcha.js"
// German strings, chosen from <html lang="de">; after the widget, which sets up the
// registry they are added to.
import "../../vendor/altcha/i18n/de.js"
