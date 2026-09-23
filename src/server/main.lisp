(uiop:define-package #:koya-server
  (:nicknames #:koya-server/main)
  (:use #:cl)
  (:import-from #:clack)
  (:import-from #:ironclad)
  (:import-from #:koya-server/app #:*app* #:install-routes)
  (:import-from #:koya-server/lib/env #:db-path #:server-port #:dev-mode-p)
  (:import-from #:koya-server/db/connection #:connect-db #:disconnect-db)
  (:import-from #:koya-server/db/migrations #:migrate)
  (:import-from #:koya-server/db/sessions #:purge-expired-sessions)
  (:import-from #:koya-server/db/schema-dump #:write-snapshot)
  (:import-from #:koya-server/lib/totp #:totp)
  (:import-from #:koya-server/lib/assets #:refresh-asset-version)
  (:export #:start
           #:stop
           #:reload
           #:main
           #:save-executable
           #:write-schema-snapshot
           #:totp-code))
(in-package #:koya-server)

(defvar *server* nil)

(defun connect-and-migrate (db)
  (connect-db db)
  (let ((applied (migrate)))
    (when applied (format t "~&[koya] applied migrations ~{~a~^, ~}~%" applied)))
  (purge-expired-sessions))

(defun start (&key (server :hunchentoot) (address "127.0.0.1") (port (server-port)) (db (db-path)))
  "Connect the database, apply migrations and start serving."
  (when *server*
    (restart-case (error "Server is already running.")
      (restart-server () :report "Restart the server" (stop))))
  (connect-and-migrate db)
  ;; :debug only in dev: with it on, an unhandled error invokes the debugger, which
  ;; in a --non-interactive image means the process exits. Off, clack answers 500.
  (setf *server* (clack:clackup *app* :server server :address address :port port :debug (dev-mode-p)))
  *server*)

(defun stop ()
  (when *server*
    (clack:stop *server*)
    (setf *server* nil)
    (disconnect-db)
    (format t "~&[koya] server stopped~%")))

(defun reload ()
  (stop)
  (asdf:load-system :koya-server/app)
  (install-routes)
  (refresh-asset-version)
  (start))

(defun main ()
  "Entry point for a deployed process: Woo on all interfaces, in this thread. Woo
takes SIGTERM and SIGINT itself and returns; the database is closed and the
process exits."
  (connect-and-migrate (db-path))
  ;; in a thread, Woo would stop on SIGTERM and leave this one waiting forever
  (clack:clackup *app* :server :woo :address "0.0.0.0" :port (server-port) :debug nil :use-thread nil)
  (disconnect-db)
  (format t "~&[koya] server stopped~%")
  (uiop:quit 0))

(defun save-executable (path)
  "Save the loaded server as an executable at PATH that runs MAIN, and exit. The
Dockerfile's last build step: the image then starts serving without loading or
compiling anything, and needs neither Quicklisp nor a C toolchain."
  ;; ironclad keeps /dev/urandom open once it has read from it; a stream saved in
  ;; the image would be dead in the next process
  (setf ironclad::*os-prng-stream* nil)
  (sb-ext:save-lisp-and-die path :executable t :toplevel #'main
                                 ;; the image takes no command line; SBCL must not read one either
                                 :save-runtime-options t))

(defun write-schema-snapshot ()
  "Regenerate src/server/db/schema.sql from the migrations. Run it after adding
one: a test fails while the snapshot is stale."
  (write-snapshot))

(defun totp-code (&optional (secret (koya-server/lib/totp:totp-secret)))
  "The one-time code valid right now, for checking a setup from the REPL."
  (totp secret))
