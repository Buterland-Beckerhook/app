# ADR 0008 — The Diashow crops to one shared frame, and the strip that scrolls it is CSS

**Status:** Accepted (2026-07-26)

**Replaces:** the slideshow renderer and its `[data-slide]` controller from
`6826083` ("separator block, gallery slideshow mode & lightbox redesign"). That
commit's separator block and lightbox redesign stand untouched.

**Refines:** [ADR 0004](0004-media-library-owns-image-metadata.md) — its rule that a
gallery image's caption is shown only on enlarging now holds for the grid layout
only.

## Context

`image_gallery` has offered two layouts since the block was created — „Raster" and
„Diashow" — but for most of that time `BbhWeb.SiteComponents.block/1` never read
`layout`, so both rendered the same square-cropped grid. `6826083` gave „Diashow" a
renderer: one image at a time in an `aspect-video` box, `object-contain` over
`bg-base-200`, slides toggled with `hidden`, navigation by pointer position (the
outer ~15% pages, the middle enlarges).

Three things about that shape are what this ADR changes, and they are the reasons
below rather than a matter of taste:

- `object-contain` in a fixed box means a landscape photo sits in a band of empty
  grey and the picture changes size from slide to slide.
- `hidden` cannot animate. There is no state between "slide 1 shown" and "slide 2
  shown" for a transition to occupy, so paging is a cut.
- The caption existed only as `data-lightbox-caption`, so it was readable only after
  enlarging — and a Diashow is already the enlarged view.

What that commit's design got right is kept: one picture at a time, dots under the
strip, and the lightbox as the way to see a photo uncropped.

Three things decide the shape of a slideshow, and all three have a wrong answer that
looks reasonable:

**A slide has to have a frame.** The obvious rendering is `object-fit: contain` —
show every photo whole. Do that and the container has to be as tall as the tallest
picture, so a landscape shot sits in a band of empty space, and stepping from a
portrait to a landscape either resizes the whole block or drops the photo into a
letterbox. Neither reads as a slideshow; both read as a bug.

**Cropping is not only a CSS concern.** `object-fit: cover` on a full-size image
crops around the *centre* of the picture. The media library already knows better —
every upload can carry a focal point, and `media_url/2` only puts it on the URL when
both dimensions are asked for (see `Format.focal_params/2`). A slideshow that crops
in the browser throws that away and cuts heads off in exactly the portrait frames
where it matters most.

**A carousel is the classic place to reinvent scrolling.** The reflex is a track with
`transform: translateX(-i * 100%)` and a touch handler. That is a re-implementation of
a scroll container: momentum, snapping, swipe, keyboard, and the animation itself all
have to be written and then re-written for each browser that disagrees.

## Decision

**Every slide is cropped to one ratio, chosen by the editor.**
`ImageGallery.aspect_ratios/0` lists `16:9 3:2 4:3 1:1 3:4 2:3 9:16` — landscape,
square and portrait, because a club gallery is as often a hall photo as a standing
portrait of a Thron. The block stores it as `W:H`, the renderer hands CSS
`aspect-ratio: W/H`, and `validate_inclusion` and the editor's dropdown both read the
same list.

**The crop is asked of the media pipeline, not just of CSS.** `slide_size/1` scales
the ratio until its longer edge is 1600px and passes both dimensions to
`media_url/2`, so the variant arrives already cut — around the focal point, at the
size actually shown. The `aspect-ratio` and `object-cover` in the markup are the
belt to that braces: if a variant ever fails to generate, the frame still holds.

**The strip is a CSS scroll-snap container** (`.bbh-slideshow-track`), not a
JS-positioned track. Swipe, momentum, snapping and the sliding animation itself
(`scroll-behavior: smooth` — the next picture pushes the current one out) are the
browser's. JavaScript adds only what a scroll container has no opinion about: arrows,
dots and a timer.

**The Diashow shows the Bildunterschrift on the page.** ADR 0004 keeps gallery
thumbnails bare and moves caption and copyright into the lightbox. That reasoning is
about *thumbnails* — a 400px tile in a grid of nine, where nine credit lines would be
more text than picture. A Diashow is already the enlarged view, one picture at a time
at full column width, so the same rule there would mean the caption is never read.
The credit line rides *inside* the slide, so it moves with its own picture rather
than swapping under a photo that is still sliding.

**Autoplay is opt-in per block, and stoppable.** Off by default; `data-slideshow-interval`
is only emitted when the editor turned it on. It pauses on hover and on keyboard focus,
halts for good the moment a visitor uses an arrow or a dot, and is not started at all
under `prefers-reduced-motion: reduce`.

## Consequences

- **The index is read from `scrollLeft`, never counted.** A swipe, a trackpad flick,
  an arrow click and the autoplay timer all end as a scroll position, so a counter
  kept alongside would be a second source of truth that drifts the first time
  somebody swipes. `nearestSlide/3` rounds the position to a slide and the dots
  follow from that; `step/3` is the only arithmetic, and both are pure and unit-tested
  in `assets/js/slideshow.test.js` — the split `tree_dnd.js` established, for the same
  reason (`node --test` has no DOM).
- **The one exception is a scroll this code started.** Reading the position while a
  smooth scroll is in flight answers with the slide being scrolled *away from*, so two
  quick clicks on the arrow were both told "you are on slide 1" and the second went
  nowhere. `heading` holds the destination until the strip has been quiet for 150ms —
  a `scrollend` the polyfill way, because Safari only learned that event recently.
  Anything the visitor drives sets no `heading` and is still read off the position.
- **A resize puts the strip back on the slide that was showing.** Changing the width
  changes what one slide is worth, and the browser answers by re-snapping to the
  start — so without this, turning a phone sideways sends the reader back to picture
  one. `settled` is recorded whenever the strip comes to rest and re-applied
  instantly on `resize` — but only when the *width* changed. A slide is as wide as its
  container, so a height-only resize cannot have moved anything, and on mobile that is
  the common one: hiding the address bar fires `resize` mid-scroll, and answering it
  with a `scrollTo` would snatch the strip away from a finger still swiping.
- **Without JavaScript the Diashow still works.** It degrades to a swipeable,
  keyboard-scrollable strip showing every picture and every caption. The arrows and
  dots are inert, which is why they are not the only way to reach a slide.
- **Wrapping at both ends is deliberate, and it cuts rather than scrolls.** Autoplay
  would otherwise die on the last picture, and a visitor at the end would have to click
  back through the whole gallery. But a wrap is a scroll across the *entire* strip:
  animated, it drags the reader past every picture in between — a rewind on three
  images, seconds of strobing on twenty, and under autoplay once per cycle. So a step
  to a neighbour animates and a wrap is instant.
- **A swipe stops autoplay, the same as an arrow does.** Hover-pause is a desktop
  affordance; on touch, `pointerenter`/`pointerleave` bracket the swipe itself, so
  resuming on `pointerleave` would restart the timer the moment the finger lifts and
  move the reader off the picture they just swiped to. The settle handler knows the
  difference — no `heading` means the scroll was visitor-driven — so it takes over.
  That also makes the WCAG 2.2.2 story hold on touch, where there is no hover.
- **The arrows sit on an overlay that repeats the slide's `aspect-ratio`.** They have
  to be centred on the *picture*, and the slide is picture plus caption — a caption
  that is one line for one photo and three for the next. Giving the overlay the same
  ratio makes it end exactly where the credit line starts, without measuring anything
  at runtime. It is `pointer-events: none` except on the buttons themselves, so it
  does not eat clicks meant for the lightbox.
- **A one-image Diashow renders no arrows and no dots**, and the controller returns
  before binding anything.
- **`1:1` asks for a 1600×1600 variant.** Scaling by the longer edge is what keeps
  `9:16` from asking for a 2844px-tall image, and the cost is that a square slide is
  larger than the column ever needs. It is one cached variant per gallery, and the
  alternative — a second table of sizes beside the ratio list — is a thing to keep in
  sync.
- **…but never larger than the picture actually is.** `Image.thumbnail/3` defaults to
  `resize: :both` and the focal crop scales by `max(w/w0, h/h0)` with no clamp, so an
  unclamped request upscales: a 640px club photo becomes a soft 1600×900 WebP that also
  costs more bytes than the original. `source_long_edge/1` caps the request at the
  upload's own longer edge. The frame is held by CSS either way, so the only thing a
  smaller variant costs is zoom headroom on a very wide screen.
- **The first slide is eager and `fetchpriority="high"`; the rest stay lazy.** A 1600px
  slide near the top of a page is the LCP element, and `loading="lazy"` on it is the
  classic way to lose a second. The grid got away with lazy at 400×400; this does not.
- **Stopping autoplay for good on the first click is how this meets WCAG 2.2.2.**
  Motion that starts by itself needs a mechanism to stop it; here the arrows and dots
  *are* that mechanism, so there is no separate pause button to explain. The
  consequence to know about: after touching a control, the Diashow stays where the
  visitor left it for the rest of the page's life.
- **`layout`'s three defaults were disagreeing, and now do not.** The column and the
  schema both defaulted to `"slideshow"` while `Content.@block_defaults` inserts
  `"grid"`. That cost nothing while nothing read `layout`; from here on it would make
  any row written outside `add_block/2` — an importer, a data migration, a hand-written
  INSERT — silently a slideshow. All three now say `"grid"`. Worth knowing before
  deploying: a `SELECT id FROM block_image_gallery WHERE layout = 'slideshow'` lists
  the blocks whose editors picked „Diashow", saw nothing happen, and left it set —
  those pages become slideshows on release. That is the feature working, but it is
  unannounced from the editor's point of view.
- **The dots are a 24px target around an 8px dot.** WCAG 2.5.8 wants 24×24, and
  `background-clip: content-box` grows the target without growing the dot. They are
  also the only thing that says how many pictures there are (the scrollbar is hidden),
  so the inactive ones sit at 0.5 rather than 0.25 opacity to clear 3:1 for SC 1.4.11.
- **The lightbox is unchanged and still available.** Clicking a slide opens the same
  full-screen viewer the grid uses, grouped by block, which is where a visitor goes to
  see the *uncropped* photo. That is the escape hatch from a frame that crops badly —
  and the reason cropping in the layout is safe at all.
- **Verified in a browser, and worth the trouble.** Contrary to what ADR 0007
  recorded, Playwright does ship an arm64 Chrome-for-Testing build; it runs here once
  the usual `libnss3`/`libgbm1`/… are installed. Driving the real thing is what turned
  up the two bugs above and a third — `aria-current={i == 0}` rendered as a *valueless*
  `aria-current`, which the spec reads as "false", so no dot looked active until the
  first scroll. All three are invisible to a markup assertion, and two of them only
  exist because a scroll container animates. `page_content_controller_test.exs` now
  pins the `aria-current` string; the other two are behaviour a DOM-less test cannot
  reach.

  **Open follow-up:** the browser spec that found them is not committed. `assets/` has
  no `package.json` and CI installs no browser, so wiring Playwright in is a change of
  its own — but the ~140-line controller in `app.js` has no automated coverage, and it
  is where all three bugs lived. Either commit a smoke spec (next → dot 1; resize →
  slide kept; hover → autoplay pauses) or push more of the state machine
  (`heading`/`settled`/`takenOver`) behind an injectable seam in `slideshow.js` so it
  can be unit-tested without a DOM.
