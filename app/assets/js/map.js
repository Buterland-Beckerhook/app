// Event location map (ADR 0014): MapLibre GL rendering a self-hosted PMTiles
// archive with the Protomaps basemap style. Everything — tiles, glyphs, sprites,
// the worker — comes from our own origin, so the CSP stays at 'self'.
//
// Markup (BbhWeb.SiteComponents.location_map/1): a hidden <figure> holding
//   <div data-location-map data-lat data-lng data-tiles-url data-bounds>
// and the OSM attribution. It is only revealed once a map is mounted, so without
// this script (or WebGL) the page shows just the address and its links.
import * as maplibregl from "../vendor/map/maplibre-gl.mjs"
import "../vendor/map/maplibre-gl.css"
import {Protocol} from "../vendor/map/pmtiles.mjs"
import {layers, namedFlavor} from "../vendor/map/basemaps.mjs"

// esbuild emits the worker as the bundle's second entry point, next to this file.
maplibregl.setWorkerUrl(new URL("./maplibre-gl-worker.js", import.meta.url).href)
maplibregl.addProtocol("pmtiles", new Protocol().tile)

const LOCALE = {
  "CooperativeGesturesHandler.WindowsHelpText": "Strg + Scrollen zum Zoomen der Karte",
  "CooperativeGesturesHandler.MacHelpText": "⌘ + Scrollen zum Zoomen der Karte",
  "CooperativeGesturesHandler.MobileHelpText": "Karte mit zwei Fingern bewegen",
  "Map.Title": "Karte",
  "Marker.Title": "Kartenmarkierung",
  "NavigationControl.ResetBearing": "Nach Norden ausrichten",
  "NavigationControl.ZoomIn": "Vergrößern",
  "NavigationControl.ZoomOut": "Verkleinern",
}

const theme = () => (document.documentElement.dataset.theme === "dark" ? "dark" : "light")

const style = (flavour, tilesUrl) => {
  const base = `${location.origin}/karte`
  return {
    version: 8,
    glyphs: `${base}/fonts/{fontstack}/{range}.pbf`,
    sprite: `${base}/sprites/v4/${flavour}`,
    sources: {
      protomaps: {
        type: "vector",
        url: `pmtiles://${new URL(tilesUrl, location.href).href}`,
      },
    },
    layers: layers("protomaps", namedFlavor(flavour), {lang: "de"}),
  }
}

const mount = (el) => {
  const {lat, lng, tilesUrl, bounds} = el.dataset
  const center = [Number(lng), Number(lat)]
  let flavour = theme()
  // Reveal first: MapLibre sizes its canvas from the container on creation.
  el.closest("figure").hidden = false

  const map = new maplibregl.Map({
    container: el,
    style: style(flavour, tilesUrl),
    center,
    zoom: 16,
    minZoom: 10,
    maxZoom: 18,
    maxBounds: bounds.split(",").map(Number),
    cooperativeGestures: true,
    // The figure's caption carries the attribution, always visible (ODbL).
    attributionControl: false,
    locale: LOCALE,
  })
  map.addControl(new maplibregl.NavigationControl({showCompass: false}))

  const color = getComputedStyle(el).getPropertyValue("--color-primary").trim() || "#15693c"
  new maplibregl.Marker({color}).setLngLat(center).addTo(map)

  // Follow the site's theme toggle with the matching basemap flavour.
  new MutationObserver(() => {
    const next = theme()
    if (next !== flavour) {
      flavour = next
      map.setStyle(style(flavour, tilesUrl))
    }
  }).observe(document.documentElement, {attributes: true, attributeFilter: ["data-theme"]})
}

const supportsWebGL = () => {
  try {
    const canvas = document.createElement("canvas")
    return !!(canvas.getContext("webgl2") || canvas.getContext("webgl"))
  } catch {
    return false
  }
}

if (supportsWebGL()) document.querySelectorAll("[data-location-map]").forEach(mount)
