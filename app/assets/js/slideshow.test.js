// Run with: node --test assets/js/slideshow.test.js  (no dependencies required)
import {test} from "node:test"
import assert from "node:assert/strict"
import {step, nearestSlide} from "./slideshow.js"

test("stepping moves one slide in the asked-for direction", () => {
  assert.equal(step(0, 1, 3), 1)
  assert.equal(step(1, 1, 3), 2)
  assert.equal(step(2, -1, 3), 1)
})

test("stepping past the end wraps around", () => {
  // A Diashow that stops at the last picture would need the visitor to walk all the way
  // back, and autoplay would simply die there.
  assert.equal(step(2, 1, 3), 0)
  assert.equal(step(0, -1, 3), 2)
})

test("a single slide has nowhere to step to", () => {
  assert.equal(step(0, 1, 1), 0)
  assert.equal(step(0, -1, 1), 0)
})

test("an empty gallery never produces a negative index", () => {
  assert.equal(step(0, 1, 0), 0)
  assert.equal(step(0, -1, 0), 0)
})

test("an index that drifted out of range is pulled back in", () => {
  // The scroll position is the source of truth, and a mid-resize read can land outside.
  assert.equal(step(7, 1, 3), 2)
  assert.equal(step(-4, 0, 3), 2)
})

test("the nearest slide is the one the strip is closest to", () => {
  const slide = 300

  assert.equal(nearestSlide(0, slide, 4), 0)
  assert.equal(nearestSlide(300, slide, 4), 1)
  assert.equal(nearestSlide(900, slide, 4), 3)
})

test("a half-scrolled strip rounds to the closer neighbour", () => {
  // Momentum scrolling and a swipe let go mid-slide both land here; the dots have to
  // pick one, and it must be the one filling most of the frame.
  assert.equal(nearestSlide(140, 300, 4), 0)
  assert.equal(nearestSlide(160, 300, 4), 1)
})

test("overscroll past either end still reports a real slide", () => {
  // iOS rubber-banding produces a negative scrollLeft and one past the last slide.
  assert.equal(nearestSlide(-80, 300, 4), 0)
  assert.equal(nearestSlide(5000, 300, 4), 3)
})

test("a strip with no width yet reports the first slide", () => {
  // Read before layout, or while the container is display:none — dividing by zero here
  // would put NaN into the dots' aria-current.
  assert.equal(nearestSlide(0, 0, 4), 0)
  assert.equal(nearestSlide(120, 0, 4), 0)
})
