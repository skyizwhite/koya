FROM fukamachi/qlot

ARG TW_VERSION=4.3.0

WORKDIR /app

RUN apt-get update \
  && apt-get install -y --no-install-recommends build-essential curl libev-dev libsqlite3-dev \
  && rm -rf /var/lib/apt/lists/*

RUN curl -sL https://github.com/tailwindlabs/tailwindcss/releases/download/v${TW_VERSION}/tailwindcss-linux-x64 -o /usr/local/bin/tailwindcss \
  && chmod +x /usr/local/bin/tailwindcss

COPY . /app
RUN qlot install

RUN qlot exec sbcl --non-interactive --eval '(ql:quickload "koya-server")'

RUN tailwindcss -i ./assets/style/global.css -o ./assets/style/dist.css --minify

ENV KOYA_DB_PATH=/data/koya.db \
    KOYA_MEDIA_DIR=/data/media \
    KOYA_PORT=3000
VOLUME ["/data"]
EXPOSE 3000

ENTRYPOINT ["qlot", "exec", "sbcl", "--non-interactive", \
            "--eval", "(ql:quickload \"koya-server\" :silent t)", \
            "--eval", "(koya-server:main)"]
