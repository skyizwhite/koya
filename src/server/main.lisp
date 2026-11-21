(uiop:define-package #:koya-server
  (:nicknames #:koya-server/main)
  (:use #:cl)
  (:import-from #:clack)
  (:import-from #:ironclad)
  (:import-from #:koya-server/infra/main
                #:db-path #:server-port #:server-workers #:open-store #:close-store #:write-snapshot
                #:check-settings #:setting-error #:setting-error-problems)
  (:import-from #:koya-server/web/app #:app #:*app* #:install-routes)
  (:import-from #:koya-server/web/lib/assets #:refresh-asset-version)
  (:import-from #:koya-server/domain/totp #:totp)
  (:import-from #:koya-server/usecases/ports/config #:dev-mode-p)
  (:import-from #:koya-server/usecases/ports/main #:+ports+)
  (:import-from #:okite #:ensure-implemented)
  (:import-from #:org.shirakumo.verbose)
  (:import-from #:piping #:find-place)
  (:import-from #:koya-server/log #:log-info #:log-warn #:log-error)
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

(defun start-logging ()
  (org.shirakumo.verbose:restart-global-controller)
  (setf (org.shirakumo.verbose:ansi-colors
         (find-place org.shirakumo.verbose:*global-controller* 'org.shirakumo.verbose:repl-faucet))
        nil))

(defun warn-about-a-short-secret ()
  (unless (owner-secret-long-enough-p)
    (log-warn :koya.server "KOYA_SECRET is shorter than ~a characters: logging in is off until it is replaced"
              +min-secret-length+)))

(defun start (&key (server :hunchentoot) (address "127.0.0.1") port (db (db-path)))
  (when *server*
    (restart-case (error "Server is already running.")
      (restart-server () :report "Restart the server" (stop))))
  (check-settings)
  (open-store db)
  (warn-about-a-short-secret)
  (log-info :koya.server "server starting on ~a:~a" address (or port (server-port)))
  (setf *server* (clack:clackup (app) :server server :address address :port (or port (server-port))
                                      :debug (dev-mode-p)))
  *server*)

(defun stop ()
  (when *server*
    (clack:stop *server*)
    (setf *server* nil)
    (close-store)
    (log-info :koya.server "server stopped")))

(defun reload ()
  (stop)
  (asdf:load-system :koya-server)
  (install-routes)
  (setf *app* nil)
  (refresh-asset-version)
  (start))

(defun quit (code)
  (org.shirakumo.verbose:flush)
  (uiop:quit code))

(defun main ()
  (start-logging)
  (handler-case (check-settings)
    (setting-error (e)
      (dolist (problem (setting-error-problems e))
        (log-error :koya.server "~a" problem))
      (quit 1)))
  (open-store (db-path))
  (warn-about-a-short-secret)
  (log-info :koya.server "server starting on 0.0.0.0:~a with ~a workers" (server-port) (server-workers))
  (clack:clackup (app) :server :woo :address "0.0.0.0" :port (server-port) :worker-num (server-workers)
                       :debug nil :use-thread nil)
  (close-store)
  (log-info :koya.server "server stopped")
  (quit 0))

(defun stop-logging ()
  (let ((thread (and org.shirakumo.verbose:*global-controller*
                     (org.shirakumo.verbose:thread org.shirakumo.verbose:*global-controller*))))
    (org.shirakumo.verbose:remove-global-controller)
    (when thread
      (sb-thread:join-thread thread :default nil))))

(defun save-executable (path)
  (setf ironclad::*os-prng-stream* nil)
  (stop-logging)
  (sb-ext:save-lisp-and-die path :executable t :toplevel #'main
                                 :save-runtime-options t))

(defun write-schema-snapshot ()
  (write-snapshot))

(defun totp-code (&optional (secret (totp-secret)))
  (totp secret))
