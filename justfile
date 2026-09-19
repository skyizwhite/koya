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

# Rebuild CSS on every change
watch:
    @{{ tw_bin }} -i {{ style_src }} -o {{ style_dist }} --watch=always

# Build the CSS once
build:
    @{{ tw_bin }} -i {{ style_src }} -o {{ style_dist }} --minify

# Run the test suite
test:
    @qlot exec ros --non-interactive -e '(handler-bind ((warning (function muffle-warning))) (ql:quickload :koya-tests :silent t))' -e '(uiop:quit (if (rove:run :koya-tests :style :dot) 0 1))' -q

# Start the server in development mode (Hunchentoot, localhost:3000)
dev:
    @qlot exec ros -e '(ql:quickload :koya-server :silent t)' -e '(koya-server:start)' -e '(loop (sleep 3600))'

# Open a REPL with the server system loaded
repl:
    @qlot exec ros -e '(ql:quickload :koya-server :silent t)' run

# Remove downloaded binaries and Lisp dependencies
clean:
    rm -rf ./bin ./.qlot
