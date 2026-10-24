#!/bin/sh
# Dev container entrypoint: fetch deps, set up assets, ensure the DB exists and
# is migrated, then start the Phoenix server with code reloading.
#
# deps.get / assets.setup are fast no-ops once the named volumes are populated.
# ecto.create / ecto.migrate are idempotent; `make seed` deliberately drops and
# restores the DB over the top of this when loading a snapshot.
set -e

mix deps.get
# Precompiled NIFs + tailwind via curl (mix's :httpc chokes on GitHub's headers).
./bin/prefetch-precompiled.sh
mix assets.setup
mix ecto.create
mix ecto.migrate

exec mix phx.server
