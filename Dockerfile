# koya: one image with the server; SQLite and uploaded media live under /data.
# Published as ghcr.io/skyizwhite/koya (see README, "Deployment"). Run it with
# port 3100 exposed, a volume at /data, and KOYA_SECRET and KOYA_BASE_URL set.

# --- build: dependencies, stylesheet, and the server saved as one executable ---
FROM fukamachi/qlot AS build

ARG TARGETARCH
ARG TW_VERSION=4.3.0

RUN apt-get update \
  && apt-get install -y --no-install-recommends build-essential curl libev-dev libsqlite3-dev \
  && rm -rf /var/lib/apt/lists/*

RUN case "${TARGETARCH:-amd64}" in \
      amd64) tw=x64 ;; \
      arm64) tw=arm64 ;; \
      *) echo "no Tailwind binary for ${TARGETARCH}" >&2; exit 1 ;; \
    esac \
  && curl -fsSL "https://github.com/tailwindlabs/tailwindcss/releases/download/v${TW_VERSION}/tailwindcss-linux-${tw}" \
       -o /usr/local/bin/tailwindcss \
  && chmod +x /usr/local/bin/tailwindcss

WORKDIR /app

# The whole project before qlot install: koya is a package-inferred system, so
# which Quicklisp releases it needs is only known from the sources. Without them
# qlot installs the locked dists but not every release the systems load.
COPY . /app
RUN qlot install

# The heap the executable gets is the one this process starts with: the saved
# image keeps its runtime options and reads none from its own command line.
# An export holds its files and the zip made of them at once, so twice the
# largest archive an import takes (512 MB), and room for the rest.
RUN qlot exec sbcl --dynamic-space-size 2048 --non-interactive \
      --eval '(ql:quickload "koya-server")' \
      --eval '(koya-server:save-executable "/app/koya")'

# after the sources: Tailwind finds the classes it generates by scanning them
RUN tailwindcss -i ./assets/style/global.css -o ./assets/style/dist.css --minify

# --- runtime: the executable, the assets it serves, and the C libraries it opens ---
FROM debian:bookworm-slim

# the source label is what links the package on GHCR to this repository
LABEL org.opencontainers.image.source="https://github.com/skyizwhite/koya" \
      org.opencontainers.image.description="koya, a small self-hosted headless CMS in Common Lisp" \
      org.opencontainers.image.licenses="AGPL-3.0-or-later"

# libzstd for SBCL's runtime, libev for Woo, libsqlite3 for the database, libssl
# and the CA bundle for webhooks over https, tzdata for the display time zone,
# curl for the health check
RUN apt-get update \
  && apt-get install -y --no-install-recommends \
       ca-certificates curl libev4 libsqlite3-0 libssl3 libzstd1 tzdata \
  && rm -rf /var/lib/apt/lists/*

ENV KOYA_ENV=production \
    KOYA_PORT=3100 \
    KOYA_DB_PATH=/data/koya.db \
    KOYA_MEDIA_DIR=/data/media

WORKDIR /app
COPY --from=build /app/koya /usr/local/bin/koya
COPY --from=build /app/assets ./assets

VOLUME ["/data"]
EXPOSE 3100

HEALTHCHECK --interval=30s --timeout=5s --start-period=30s --retries=3 \
  CMD curl -fsS "http://localhost:${KOYA_PORT}/health" || exit 1

# Woo on all interfaces (koya-server:main), blocking.
ENTRYPOINT ["koya"]
