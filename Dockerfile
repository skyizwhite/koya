# koya: a single image with the server, SQLite and uploaded media under /data.
# Deployed on Coolify as a Dockerfile app: expose port 3000, mount a volume at
# /data, and set KOYA_SECRET and KOYA_BASE_URL (see README, "Deployment").
FROM fukamachi/qlot

ARG TW_VERSION=4.3.0
ENV KOYA_ENV=production \
    KOYA_PORT=3000 \
    KOYA_DB_PATH=/data/koya.db \
    KOYA_MEDIA_DIR=/data/media

WORKDIR /app

RUN apt-get update \
  && apt-get install -y --no-install-recommends build-essential curl libev-dev libsqlite3-dev \
  && rm -rf /var/lib/apt/lists/*

RUN curl -sL https://github.com/tailwindlabs/tailwindcss/releases/download/v${TW_VERSION}/tailwindcss-linux-x64 -o /usr/local/bin/tailwindcss \
  && chmod +x /usr/local/bin/tailwindcss

# The whole project before qlot install: koya is a package-inferred system, so
# resolving its dependencies needs the sources, not just the .asd files.
COPY . /app
RUN qlot install

# Compile everything at build time; the same user runs the container, so the
# fasls in ~/.cache are reused and startup only loads them.
RUN qlot exec sbcl --non-interactive --eval '(ql:quickload "koya-server")'
RUN tailwindcss -i ./assets/style/global.css -o ./assets/style/dist.css --minify

VOLUME ["/data"]
EXPOSE 3000

HEALTHCHECK --interval=30s --timeout=5s --start-period=60s --retries=3 \
  CMD curl -fsS "http://localhost:${KOYA_PORT}/health" || exit 1

# Woo on all interfaces (koya-server:main), blocking.
ENTRYPOINT ["qlot", "exec", "sbcl", "--non-interactive", \
            "--eval", "(ql:quickload \"koya-server\" :silent t)", \
            "--eval", "(koya-server:main)"]
