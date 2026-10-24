#!/bin/sh
# Prefetch precompiled build artifacts from GitHub releases with curl, so mix never
# has to download them itself.
#
# Why: mix and the precompiler deps download with Erlang's :httpc, which caps a
# response's headers at 10 KB (HTTP_MAX_HEADER_SIZE, not configurable). GitHub's
# release-download redirect now carries a ~9 KB Content-Security-Policy header,
# which pushes it over the cap: every such download fails with `header_too_long`.
# curl has no such limit. Drop this script once :httpc or GitHub fixes the problem.
#
# Covers:
#   - elixir_make NIFs (vix, lazy_html) -> $ELIXIR_MAKE_CACHE_DIR, sha256-verified
#     against the dep's checksum.exs, the same way elixir_make checks them;
#   - the tailwind CLI -> _build/tailwind-<target>-<version>, which
#     `mix tailwind.install --if-missing` accepts as already installed.
# mdex_native (rustler_precompiled) instead downloads from its Cloudflare mirror;
# see `config :mdex_native, artifact_source:` in config/config.exs.
#
# Run from the app directory, after `mix deps.get`. Linux only (dev container,
# release builder, CI); anywhere else this does nothing. Re-running is cheap: files
# that are already present are skipped.
set -eu

[ "$(uname -s)" = Linux ] || exit 0

case "$(uname -m)" in
  aarch64 | arm64) cc_arch=aarch64 tw_target=linux-arm64 ;;
  x86_64 | amd64) cc_arch=x86_64 tw_target=linux-x64 ;;
  *) echo "prefetch-precompiled: unsupported arch $(uname -m), skipping" >&2; exit 0 ;;
esac

cache_dir="${ELIXIR_MAKE_CACHE_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}/elixir_make}"
mkdir -p "$cache_dir"

# fetch <url> <dest> [sha256]
fetch() {
  [ -s "$2" ] && return 0
  echo "prefetch-precompiled: $1"
  curl -fsSL --retry 3 -o "$2.part" "$1"
  if [ -n "${3:-}" ] && ! echo "$3  $2.part" | sha256sum -c --status; then
    echo "prefetch-precompiled: checksum mismatch for $1" >&2
    rm -f "$2.part"
    exit 1
  fi
  mv "$2.part" "$2"
}

# elixir_make deps: <dep> <GitHub repo>. Every artifact for this arch is fetched
# (one per NIF version, a few MB each); elixir_make picks the one it needs.
for entry in vix:akash-akya/vix lazy_html:dashbitco/lazy_html; do
  dep="${entry%%:*}"
  repo="${entry#*:}"
  checksums="deps/$dep/checksum.exs"
  [ -f "$checksums" ] || continue

  # Lines look like:  "vix-nif-2.17-aarch64-linux-gnu-0.42.0.tar.gz" => "sha256:…",
  grep -o "\"$dep-nif-[^\"]*-$cc_arch-linux-gnu-[^\"]*\" => \"sha256:[0-9a-f]*\"" "$checksums" |
    sed 's/"\([^"]*\)" => "sha256:\([0-9a-f]*\)"/\1 \2/' |
    while read -r file sum; do
      version="${file##*-}"
      version="${version%.tar.gz}"
      fetch "https://github.com/$repo/releases/download/v$version/$file" "$cache_dir/$file" "$sum"
    done
done

# tailwind CLI: the version comes from `config :tailwind, version: "…"`.
tw_version="$(sed -n '/^config :tailwind/,/^$/s/.*version: "\([^"]*\)".*/\1/p' config/config.exs)"
if [ -n "$tw_version" ]; then
  mkdir -p _build
  bin="_build/tailwind-$tw_target-$tw_version"
  fetch "https://github.com/tailwindlabs/tailwindcss/releases/download/v$tw_version/tailwindcss-$tw_target" "$bin"
  chmod +x "$bin"
fi
