// URL slug generation, kept as a pure, import-free module so it can be unit
// tested with `node --test` (no bundler, no DOM). Mirrors the server-side
// Mix.Tasks.Bbh.Import.slugify/1: lowercase, transliterate German umlauts,
// collapse every run of non-alphanumerics to a single dash, trim dashes off
// the edges. Keep the two in sync.
const UMLAUTS = {ä: "ae", ö: "oe", ü: "ue", ß: "ss"}

export function slugify(s) {
  return (s || "")
    .toLowerCase()
    .replace(/[äöüß]/g, c => UMLAUTS[c])
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-+|-+$/g, "")
}
