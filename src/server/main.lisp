(uiop:define-package #:koya-server
  (:nicknames #:koya-server/main)
  (:use #:cl)
  (:import-from #:clack)
  (:import-from #:ironclad)
  (:import-from #:koya-server/infra/main
                #:db-path #:server-port #:open-store #:close-store #:write-snapshot)
  (:import-from #:koya-server/web/app #:app #:*app* #:install-routes)
  (:import-from #:koya-server/web/assets #:refresh-asset-version)
  (:import-from #:koya-server/domain/totp #:totp)
  (:import-from #:koya-server/usecases/ports/config #:dev-mode-p)
  (:import-from #:koya-server/usecases/ports/main #:+ports+)
  (:import-from #:okite #:ensure-implemented)
  (:import-from #:koya-server/usecases/settings/two-factor #:totp-secret)
  (:export #:start
           #:stop
           #:reload
           #:main
           #:save-executable
           #:write-schema-snapshot
           #:totp-code))
(in-package #:koya-server)

;;; The composition root: the one place that loads infra, whose modules add the
;;; methods of the ports the use cases call (usecases/ports/store), and starts
;;; the web app on top.

;; when this file loads, infra has: a port it leaves out would otherwise be found
;; only when a request first calls it
(ensure-implemented +ports+)

(defvar *server* nil)

(defun start (&key (server :hunchentoot) (address "127.0.0.1") (port (server-port)) (db (db-path)))
  "Connect the database, apply migrations and start serving."
  (when *server*
    (restart-case (error "Server is already running.")
      (restart-server () :report "Restart the server" (stop))))
  (open-store db)
  ;; :debug only in dev: with it on, an unhandled error invokes the debugger, which
  ;; in a --non-interactive image means the process exits. Off, clack answers 500.
  (setf *server* (clack:clackup (app) :server server :address address :port port :debug (dev-mode-p)))
  *server*)

(defun stop ()
  (when *server*
    (clack:stop *server*)
    (setf *server* nil)
    (close-store)
    (format t "~&[koya] server stopped~%")))

(defun reload ()
  (stop)
  ;; the whole system: web/app alone reaches no infra, so an edited store
  ;; method would stay the old one
  (asdf:load-system :koya-server)
  (install-routes)
  ;; built again from the code just loaded
  (setf *app* nil)
  (refresh-asset-version)
  (start))

(defun main ()
  "Entry point for a deployed process: Woo on all interfaces, in this thread. Woo
takes SIGTERM and SIGINT itself and returns; the database is closed and the
process exits."
  (open-store (db-path))
  ;; in a thread, Woo would stop on SIGTERM and leave this one waiting forever
  (clack:clackup (app) :server :woo :address "0.0.0.0" :port (server-port) :debug nil :use-thread nil)
  (close-store)
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
                                 ;; the image takes no command line; SBCL must not read one either,
                                 ;; and the heap is the one the saving process has (Dockerfile)
                                 :save-runtime-options t))

(defun write-schema-snapshot ()
  "Regenerate src/server/infra/db/schema.sql from the migrations. Run it after adding
one: a test fails while the snapshot is stale."
  (write-snapshot))

(defun totp-code (&optional (secret (totp-secret)))
  "The one-time code valid right now, for checking a setup from the REPL."
  (totp secret))
