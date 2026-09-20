(uiop:define-package #:koya-server
  (:nicknames #:koya-server/main)
  (:use #:cl)
  (:import-from #:clack)
  (:import-from #:koya-server/app #:*app*)
  (:import-from #:koya-server/lib/env #:db-path #:server-port)
  (:import-from #:koya-server/db/connection #:connect-db #:disconnect-db)
  (:import-from #:koya-server/db/migrations #:migrate)
  (:import-from #:koya-server/lib/totp #:generate-totp-secret #:otpauth-uri #:totp)
  (:import-from #:koya-server/lib/assets #:refresh-asset-version)
  (:export #:start
           #:stop
           #:reload
           #:main
           #:totp-setup
           #:totp-code))
(in-package #:koya-server)

(defvar *server* nil)

(defun start (&key (server :hunchentoot) (address "127.0.0.1") (port (server-port)) (db (db-path)))
  "Connect the database, apply migrations and start serving."
  (when *server*
    (restart-case (error "Server is already running.")
      (restart-server () :report "Restart the server" (stop))))
  (connect-db db)
  (let ((applied (migrate)))
    (when applied (format t "~&[koya] applied migrations ~{~a~^, ~}~%" applied)))
  (setf *server* (clack:clackup *app* :server server :address address :port port))
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
  (refresh-asset-version)
  (start))

(defun main ()
  "Entry point for a deployed process: Woo on all interfaces, blocking forever."
  (start :server :woo :address "0.0.0.0")
  (loop (sleep 3600)))

(defun totp-setup (&key (account "owner"))
  "For configuring two-factor login through the environment instead of the admin
UI's settings page: generate a secret and print the KOYA_TOTP_SECRET line and
the otpauth URI for an authenticator app. Returns the secret."
  (let ((secret (generate-totp-secret)))
    (format t "~&KOYA_TOTP_SECRET=~a~%~a~%" secret (otpauth-uri secret :account account))
    secret))

(defun totp-code (&optional (secret (koya-server/lib/totp:totp-secret)))
  "The one-time code valid right now, for checking a setup from the REPL."
  (totp secret))
