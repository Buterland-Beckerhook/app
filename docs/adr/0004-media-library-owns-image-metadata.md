# ADR 0004 — The media library owns image metadata; rotation rewrites the original

**Status:** Accepted (2026-07-26)

**Refined by:** [ADR 0008](0008-gallery-slideshow.md) — "a gallery image's caption
appears only on enlarging" is now the *grid* layout's rule. The Diashow shows the
credit line on the page, because it is already the enlarged view.

## Context

Image text lived in three places at once. `media` carried `title`,
`description` and `copyright`; `article_images` carried its *own* `title`,
`description` and `copyright`; `block_gallery_files` carried `title` and
`copyright` again. Editors therefore had to fill in the same caption twice —
once in the media library, once at the embedding — and the two silently drifted
apart (in the imported data 227 of 477 rows disagreed on the copyright wording
alone). Worse, none of it was ever rendered: no public template read a caption
or a copyright, so the credit an editor typed simply vanished.

Two more consequences of the same split: the picker at each embedding site was
its own little grid over `Media.list_uploads(search:)`, so none of them could
browse the folders the library had had since 2026-07-15 (you had to know the
file name), and the gallery block had no image management at all.

Separately, editors need to straighten pictures that come off a phone or scanner
sideways — a 90° rotation in the admin.

## Decision

**One owner per fact.** Caption (`media.caption`, new), alt text
(`media.description`), copyright and title belong to the media item and are
edited only in the media library modal (`BbhWeb.Admin.MediaEditor`). An
embedding keeps only embedding decisions: `article_images.show_caption` (new),
`use_as_throne_picture`, `use_as_article_image`, `sort`. The duplicated columns
were folded into `media` by migration and dropped.

**One picker.** `BbhWeb.Admin.MediaPicker` (a LiveComponent, replacing
`MediaPickerComponent`) is the single folder-aware chooser for article images,
the Bild-Karte, the gallery block and the Trix toolbar. Browsing is
folder-scoped; searching spans all folders on purpose, so a misfiled picture is
still reachable.

**Rotation is destructive.** `Bbh.Media.rotate_upload/2` bakes in EXIF
orientation (`Image.autorotate/1`), turns the pixels (`Image.rotate/2`, a
discrete vips `rot` for quarter turns), writes a temporary file and only then
renames it over the original.

## Consequences

- Ordering came for free with the consolidation: `has_many :images` /
  `has_many :files` now declare `preload_order: [asc: :sort, asc: :inserted_at]`,
  so *every* preload — article page, homepage, /thron, search indexer — follows
  the editor's order. Previously each of seven query sites would have needed its
  own `order_by`, and none had one.
- Rotating in place is what makes the new orientation appear everywhere at once,
  including plain `/media/<key>` downloads and images already embedded in
  rich-text bodies (whose `<img src>` is frozen at insert time and would not
  survive a new storage key). The price is one re-encode per turn (quality 90;
  invisible next to the WebP-82 variants that are actually served) — and it
  *compounds*: turning back is not an undo, it is three more generations of
  lossy re-encoding. Lossless quarter-turn rotation is not reachable through
  `Image.write/3`, so this is accepted rather than solved.
- Cache invalidation needs three parts, because deleting the stale files is not
  enough on its own:
  - *Disk, correctness*: `media.revision` joins the variant cache key (only once
    it is non-zero, so entries written before rotation existed stay valid). This
    is what makes a stale variant **unreachable** rather than merely deleted — a
    generation already in flight when a rotation purges the directory finishes
    afterwards and writes the pre-rotation image back under the name it computed
    at the start. Without the revision in the key, that resurrected file is what
    every later request finds on disk, and the picture stays sideways forever.
    The cost is one indexed lookup per *variant* request (`resolve_variant/5`);
    serving an original still touches no database. The revision is read from the
    database, never from the client's `?v=`, which would otherwise let anyone
    mint unbounded cache entries.
  - *Disk, housekeeping*: variants moved from one flat cache directory into one
    directory per upload (`<cache>/<sha256(storage_key)>/<sha256(size…)>.webp`).
    Their file names are content hashes, so a per-upload directory is the only
    way to find them all — `Media.purge_variants/1` drops it after a rotation,
    and `delete_upload/1` now cleans up too instead of orphaning variants
    forever. Pre-existing flat cache files become orphans; the cache is
    regenerable by design (and excluded from backups), so they can be deleted.
  - *Browser*: the same `revision` rides on media URLs as `?v=<n>`. Without it,
    `Cache-Control: max-age=604800` would keep serving the old orientation for a
    week.
- libvips memoizes operations keyed by *file name* and does not notice the bytes
  underneath changing, so a rotation also has to drop the vips operation cache —
  otherwise `Image.open` still hands back the pre-rotation image and the new
  width/height are stored wrong. Measured scope: only the plain opens are
  affected; `Image.thumbnail` on a path is non-cacheable (sequential-access
  loader), so variant generation always reads the file. The flush is therefore
  load-bearing for exactly one caller, `dimensions/1` in `store_rotation/3` — if
  that call ever goes away, so should the flush.
- GIF and SVG are not rotatable: a rewrite would drop a GIF's animation and
  rasterize an SVG. The buttons are simply absent for them, and
  `rotate_upload/2` refuses with `{:error, :not_rotatable}`.
- Rotation is wired as a *submit* of the metadata form rather than its own
  event, so text typed but not yet saved survives the turn.
- In the fold, the **media value always wins** and the embedding only fills gaps.
  `article_images.copyright` carries a column default nobody typed
  (`'Buterland-Beckerhook e.V.'`), so preferring the embedding would silently
  overwrite a photographer credit an editor had entered in the library — and the
  live data holds several ("Westfälische Nachrichten", "Sandra Doetkotte", …).
  The cost is that the club's own credit keeps whatever wording `media` had, so
  some rows read "Buterland-Beckerhook" without the "e.V."; that is a one-line
  edit in the library, whereas a lost photographer credit is unrecoverable.
- The migration's `down` recreates the dropped columns **empty** and does not
  revert the `media` rows `up` filled in — a rollback is not a restore.
- `show_caption` defaults to `true`, so on deploy every historical article image
  starts showing the caption folded in from `article_images.title`. That is the
  point (the text was never rendered before), but it is a one-shot, site-wide
  content change: the captions come from Hugo front matter and were never
  proofread as public copy. Per-image opt-out is one checkbox in the article
  form.
