// Index arithmetic for the gallery block's "Diashow" layout
// (BbhWeb.SiteComponents.gallery_slideshow).
//
// Only the part that is a real decision lives here, free of any DOM access, so it can
// be unit-tested with `node --test` (see slideshow.test.js). Everything else —
// listeners, scrollTo, the autoplay timer — is browser plumbing and stays in the
// controller in app.js.
//
// The strip itself is a CSS scroll-snap container (`.bbh-slideshow-track` in app.css),
// so swiping, the snap and the sliding animation are the browser's job and survive with
// JavaScript switched off. That also makes the scroll position — not a counter — the
// source of truth: a swipe, a trackpad flick and an arrow click all end as a scrollLeft,
// so reading it back is the only way the dots cannot drift out of sync with the picture.

/**
 * The slide `delta` steps away from `current`, wrapping around both ends.
 *
 * Wrapping is what keeps autoplay alive past the last picture and saves a visitor at
 * the end from clicking back through the whole gallery. Out-of-range input is folded
 * back in rather than trusted.
 *
 * @param {number} current
 * @param {number} delta - usually +1 or -1
 * @param {number} count - number of slides
 * @returns {number} an index within [0, count), or 0 when there are no slides
 */
export function step(current, delta, count) {
  if (count < 1) return 0
  return (((current + delta) % count) + count) % count
}

/**
 * The slide a strip scrolled to `scrollLeft` is showing — the closest one, so a swipe
 * released mid-slide reports whichever picture fills most of the frame.
 *
 * @param {number} scrollLeft
 * @param {number} slideWidth - width of one slide in px
 * @param {number} count - number of slides
 * @returns {number} an index within [0, count)
 */
export function nearestSlide(scrollLeft, slideWidth, count) {
  if (!slideWidth || count < 1) return 0
  return Math.min(count - 1, Math.max(0, Math.round(scrollLeft / slideWidth)))
}
