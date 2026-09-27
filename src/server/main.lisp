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
  (:import-from #:koya-server/usecases/settings #:totp-secret)
  (:import-from #:koya-server/usecases/auth #:owner-secret-long-enough-p #:+min-secret-length+)
  (:export #:start
           #:stop
           #:reload
           #:main
           #:save-executable
           #:write-schema-snapshot
           #:totp-code))
(in-package #:koya-server)

(ensure-implemented +ports+)

(defvar *server* nil)

(defun warn-about-a-short-secret ()
  (unless (owner-secret-long-enough-p)
    (format t "~&[koya] KOYA_SECRET is shorter than ~a characters: logging in is off until it is replaced~%"
            +min-secret-length+)))

(defun start (&key (server :hunchentoot) (address "127.0.0.1") (port (server-port)) (db (db-path)))
  (when *server*
    (restart-case (error "Server is already running.")
      (restart-server () :report "Restart the server" (stop))))
  (open-store db)
  (warn-about-a-short-secret)
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
  (asdf:load-system :koya-server)
  (install-routes)
  (setf *app* nil)
  (refresh-asset-version)
  (start))

(defun main ()
  (open-store (db-path))
  (warn-about-a-short-secret)
  (clack:clackup (app) :server :woo :address "0.0.0.0" :port (server-port) :debug nil :use-thread nil)
  (close-store)
  (format t "~&[koya] server stopped~%")
  (uiop:quit 0))

(defun save-executable (path)
  (setf ironclad::*os-prng-stream* nil)
  (sb-ext:save-lisp-and-die path :executable t :toplevel #'main
                                 :save-runtime-options t))

(defun write-schema-snapshot ()
  (write-snapshot))

(defun totp-code (&optional (secret (totp-secret)))
  (totp secret))
