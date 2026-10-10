tw_version := "4.3.0"
tw_bin     := "./bin/tailwindcss"
style_src  := "./assets/style/global.css"
style_dist := "./assets/style/dist.css"
tw_platform := "linux-x64"

[private]
default:
    @just --list

# Download the Tailwind CSS binary and install Lisp dependencies
install:
    mkdir -p ./bin
    curl -sLo {{ tw_bin }} https://github.com/tailwindlabs/tailwindcss/releases/download/v{{ tw_version }}/tailwindcss-{{ tw_platform }}
    chmod +x {{ tw_bin }}
    qlot install
    git config core.hooksPath .githooks

# Rebuild CSS on every change
watch:
    @{{ tw_bin }} -i {{ style_src }} -o {{ style_dist }} --watch=always

# Build the CSS once
build:
    @{{ tw_bin }} -i {{ style_src }} -o {{ style_dist }} --minify

# Lint the source and the spec
lint:
    @mallet src spec

# Run the spec
spec:
    @qlot exec sbcl --non-interactive --eval '(handler-bind ((warning (function muffle-warning))) (ql:quickload :koya-spec :silent t))' --eval '(uiop:quit (if (rove:run :koya-spec :style :dot) 0 1))'

# Build the CSS and start the server in development mode (Hunchentoot, localhost:3100)
dev: build
    @qlot exec sbcl --eval '(ql:quickload :koya-server :silent t)' --eval '(koya-server:start)' --eval '(handler-case (loop (sleep 3600)) (sb-sys:interactive-interrupt () (koya-server:stop) (uiop:quit 0)))'

# Open a REPL with the server system loaded
repl:
    @qlot exec sbcl --eval '(ql:quickload :koya-server :silent t)'

# Remove downloaded binaries and Lisp dependencies
clean:
    rm -rf ./bin ./.qlot
