// Geometry and payload types for drag & drop in the admin media folder tree.
//
// Only the part that is a real decision lives here, free of any DOM access, so it can
// be unit-tested with `node --test` (see tree_dnd.test.js). Everything else — listeners,
// dataTransfer, pushEvent — is browser plumbing and stays in the hooks in app.js.

// Custom MIME types rather than a shared "text/plain" payload: dataTransfer values are
// unreadable during dragover (only the *types* are exposed), so the type itself has to
// carry what is being dragged for a row to decide whether it is a valid target.
export const FOLDER_TYPE = "application/x-bbh-folder"
export const MEDIA_TYPE = "application/x-bbh-media"

/**
 * Where a drop at `clientY` over the row `rect` should land: "before" or "after" file
 * the dragged folder between siblings, "into" nests it inside the row.
 *
 * With nesting allowed the middle half means "into" and the outer quarters mean
 * "between" — a quarter is narrow enough that hitting it reads as deliberate. With
 * nesting refused (the row is already a sub-folder, or the dragged folder has children
 * of its own and the two-level cap forbids it) the row splits in half instead, so every
 * pixel still resolves to a reorder rather than a dead zone.
 *
 * @param {{top: number, height: number}} rect
 * @param {number} clientY
 * @param {{allowInto?: boolean}} options
 * @returns {"before" | "into" | "after"}
 */
export function dropIntent(rect, clientY, {allowInto = true} = {}) {
  const height = rect.height

  // A row mid-patch or not laid out yet has no meaningful geometry to divide up.
  if (!height) return allowInto ? "into" : "before"

  const offset = clientY - rect.top

  if (!allowInto) return offset < height / 2 ? "before" : "after"
  if (offset < height * 0.25) return "before"
  if (offset > height * 0.75) return "after"
  return "into"
}
