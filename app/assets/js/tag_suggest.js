// Tag suggestions for the article form's TagInput hook, kept import-free so it can be
// unit tested with `node --test`. Case-insensitive; tags starting with the query come
// before tags merely containing it, each group A–Z. A blank query lists everything.
export function matchTags(tags, query, limit = 50) {
  const q = (query || "").trim().toLowerCase()
  const lower = t => t.toLowerCase()
  const byName = (a, b) => lower(a).localeCompare(lower(b), "de")

  const prefix = tags.filter(t => lower(t).startsWith(q)).sort(byName)
  const inner = tags.filter(t => !lower(t).startsWith(q) && lower(t).includes(q)).sort(byName)

  return prefix.concat(inner).slice(0, limit)
}
