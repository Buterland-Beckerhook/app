# This file is based on these images:
#
#   - https://hub.docker.com/r/hexpm/elixir/tags - for the builder image
#     E.g.: docker.io/hexpm/elixir:1.20.4-erlang-29.1.2-debian-trixie-20261020-slim
#   - https://hub.docker.com/_/debian/tags?name=trixie-20261020-slim - for the runner image
#     E.g.: docker.io/debian:trixie-20261020-slim
#
# Find builder and runner images on Docker Hub or on Hex's Build Server (Bob).
# We recommend using Bob's Web UI to find recent tags:
#
#   - https://bob.hex.pm/docker
#
# We suggest using the same Debian version for both the builder and runner images.
#
# We suggest Debian/Ubuntu instead of Alpine to avoid production compatibility issues
# (such as DNS resolution failures, and dynamically linked NIFs/precompiled binaries).
#
# For finding packages in Debian, search on https://packages.debian.org/.

# renovate: datasource=hexpm-bob depName=elixir
ARG ELIXIR_VERSION=1.20.4
# renovate: datasource=hexpm-bob depName=erlang versioning=semver-coerced
ARG OTP_VERSION=29.1.2
# renovate: datasource=docker depName=debian versioning=debian
ARG DEBIAN_VERSION=trixie-20261020-slim

ARG BUILDER_IMAGE="docker.io/hexpm/elixir:${ELIXIR_VERSION}-erlang-${OTP_VERSION}-debian-${DEBIAN_VERSION}"
ARG RUNNER_IMAGE="docker.io/debian:${DEBIAN_VERSION}"

FROM ${BUILDER_IMAGE} AS builder

# install build dependencies
RUN apt-get update \
  && apt-get install -y --no-install-recommends build-essential git curl ca-certificates \
  && rm -rf /var/lib/apt/lists/*

# prepare build dir
WORKDIR /app

# install hex + rebar
RUN mix local.hex --force \
  && mix local.rebar --force

# set build ENV
ENV MIX_ENV="prod"

# install mix dependencies
COPY mix.exs mix.lock ./
RUN mix deps.get --only $MIX_ENV
RUN mkdir config

# copy compile-time config files before we compile dependencies
# to ensure any relevant config change will trigger the dependencies
# to be re-compiled.
COPY config/config.exs config/${MIX_ENV}.exs config/

# fetch precompiled NIFs + tailwind with curl — mix's :httpc can't download from
# GitHub releases (header size limit, see the script)
COPY bin/prefetch-precompiled.sh bin/
RUN ./bin/prefetch-precompiled.sh
RUN mix deps.compile

RUN mix assets.setup

COPY priv priv

COPY lib lib

# Compile the release
RUN mix compile

COPY assets assets

# compile assets
RUN mix assets.deploy

# Changes to config/runtime.exs don't require recompiling the code
COPY config/runtime.exs config/

COPY rel rel
RUN mix release

# start a new build stage so that the final image will only contain
# the compiled release and other runtime necessities
FROM ${RUNNER_IMAGE} AS final

RUN apt-get update \
  && apt-get install -y --no-install-recommends libstdc++6 openssl libncurses6 locales tzdata ca-certificates curl xz-utils \
  && rm -rf /var/lib/apt/lists/*

# `pmtiles` CLI for the map archive (Bbh.Workers.MapTilesUpdater, ADR 0014): one
# static binary, pinned and checksum-verified. A version bump needs both checksums
# from the release's checksums.txt (Renovate opens it for review, never auto-merges).
# renovate: datasource=github-releases depName=protomaps/go-pmtiles
ARG PMTILES_VERSION=1.31.2
ARG PMTILES_SHA256_AMD64=3ed7dbf4ec2e6dfe5e25b6f70d1ffc932729f93c86db353bf514dd71010a312f
ARG PMTILES_SHA256_ARM64=f8bd47e7ea866863489cad588fbaf2f31f42e5821f7a03f009b3769f05801cb1
ARG TARGETARCH
RUN case "${TARGETARCH:-$(dpkg --print-architecture)}" in \
      amd64) arch=x86_64; sum="${PMTILES_SHA256_AMD64}" ;; \
      arm64) arch=arm64; sum="${PMTILES_SHA256_ARM64}" ;; \
      *) echo "no pmtiles build for this architecture" >&2; exit 1 ;; \
    esac \
  && curl -fsSL -o /tmp/pmtiles.tar.gz \
       "https://github.com/protomaps/go-pmtiles/releases/download/v${PMTILES_VERSION}/go-pmtiles_${PMTILES_VERSION}_Linux_${arch}.tar.gz" \
  && echo "${sum}  /tmp/pmtiles.tar.gz" | sha256sum -c - \
  && tar -xzf /tmp/pmtiles.tar.gz -C /usr/local/bin pmtiles \
  && rm /tmp/pmtiles.tar.gz \
  && pmtiles version

# `typst` CLI for the membership application PDF (Bbh.Tickets.Pdf): one static
# binary, pinned and checksum-verified like pmtiles above. A version bump needs both checksums
# (the release assets' sha256 digests); Renovate opens it for review.
# renovate: datasource=github-releases depName=typst/typst
ARG TYPST_VERSION=0.15.1
ARG TYPST_SHA256_AMD64=a6d077d0a95eed5a2eba715b2dae06be954f624ccbf85758a03f389ded33118c
ARG TYPST_SHA256_ARM64=5aa8d74a3d906e60ea12a66ac2f37f8eef1b14cbad7182a745e393a10c23dcee
RUN case "${TARGETARCH:-$(dpkg --print-architecture)}" in \
      amd64) arch=x86_64; sum="${TYPST_SHA256_AMD64}" ;; \
      arm64) arch=aarch64; sum="${TYPST_SHA256_ARM64}" ;; \
      *) echo "no typst build for this architecture" >&2; exit 1 ;; \
    esac \
  && curl -fsSL -o /tmp/typst.tar.xz \
       "https://github.com/typst/typst/releases/download/v${TYPST_VERSION}/typst-${arch}-unknown-linux-musl.tar.xz" \
  && echo "${sum}  /tmp/typst.tar.xz" | sha256sum -c - \
  && tar -xJf /tmp/typst.tar.xz -C /tmp \
  && mv "/tmp/typst-${arch}-unknown-linux-musl/typst" /usr/local/bin/typst \
  && rm -rf /tmp/typst.tar.xz "/tmp/typst-${arch}-unknown-linux-musl" \
  && typst --version

# Set the locale
RUN sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen \
  && locale-gen

ENV LANG=en_US.UTF-8
ENV LANGUAGE=en_US:en
ENV LC_ALL=en_US.UTF-8

# OS time zone for log timestamps and OS-level local time. Overridden at runtime by
# the TZ env (compose sets it from TIME_ZONE). Elixir's DateTime conversions use the
# app-level config (Bbh.Time), not this, so the two are kept in sync via TIME_ZONE.
ENV TZ=Europe/Berlin

WORKDIR "/app"
RUN chown nobody /app

# set runner ENV
ENV MIX_ENV="prod"

# Only copy the final release from the build stage
COPY --from=builder --chown=nobody:root /app/_build/${MIX_ENV}/rel/bbh ./

# The uploads volume mounts at /data (UPLOADS_DIR=/data/uploads,
# MEDIA_CACHE_DIR=/data/uploads_cache, the map archive in /data/map). Create the mountpoint owned by the runtime
# user so an *empty* named volume is initialised nobody-writable — otherwise a
# fresh deploy gets a root-owned /data and the app can't store uploads or
# regenerate image variants.
RUN mkdir -p /data && chown nobody:root /data

USER nobody

# If using an environment that doesn't automatically reap zombie processes, it is
# advised to add an init process such as tini via `apt-get install`
# above and adding an entrypoint. See https://github.com/krallin/tini for details
# ENTRYPOINT ["/tini", "--"]

CMD ["/app/bin/server"]
