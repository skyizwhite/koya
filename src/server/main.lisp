(uiop:define-package #:koya-server
  (:nicknames #:koya-server/main)
  (:use #:cl)
  (:import-from #:clack)
  (:import-from #:koya-server/app #:*app*)
  (:import-from #:koya-server/lib/env #:db-path #:server-port)
  (:import-from #:koya-server/db/connection #:connect-db #:disconnect-db)
  (:import-from #:koya-server/db/migrations #:migrate)
  (:export #:start
           #:stop
           #:reload
           #:main))
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
  (start))

(defun main ()
  "Entry point for a deployed process: Woo on all interfaces, blocking forever."
  (start :server :woo :address "0.0.0.0")
  (loop (sleep 3600)))
