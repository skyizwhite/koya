(defpackage #:koya-server/lib/auth
  (:use #:cl)
  (:import-from #:koya-server/lib/env
                #:koya-secret)
  (:import-from #:koya-server/lib/http
                #:fail-api #:header #:json-response #:error-object #:origin-allowed-p)
  (:import-from #:koya-server/db/api-keys
                #:space-for-api-key)
  (:import-from #:ironclad
                #:constant-time-equal)
  (:import-from #:babel
                #:string-to-octets)
  (:import-from #:bordeaux-threads-2)
  (:import-from #:koya-server/lib/totp
                #:totp-enabled-p #:totp-code-valid-p)
  (:export #:secure-string=
           #:login-locked-p
           #:note-login-failure
           #:clear-login-failures
           #:owner-env-p
           #:*admin-auth-middleware*
           #:require-api-key
           #:session-login
           #:session-logout
           #:session-owner-p))
(in-package #:koya-server/lib/auth)

;;; Two kinds of callers:
;;;  - the owner: admin UI (session cookie) and admin API (Bearer KOYA_SECRET)
;;;  - sites: delivery API with a per-space API key

(defun secure-string= (a b)
  (and (stringp a) (stringp b)
       (= (length a) (length b))
       (constant-time-equal (string-to-octets a :encoding :utf-8) (string-to-octets b :encoding :utf-8))))

(defun bearer-token (env)
  (let ((auth (gethash "authorization" (getf env :headers))))
    (and auth (> (length auth) 7) (string-equal (subseq auth 0 7) "Bearer ")
         (string-trim " " (subseq auth 7)))))

(defun session-owner-p (&optional (session (ningle:context :session)))
  (and session (gethash "owner" session) t))

;;; Failed logins are counted per client address; after +LOGIN-ATTEMPTS+ failures
;;; within +LOGIN-WINDOW-SECONDS+ the address has to wait. Kept in memory: one
;;; process, and a restart clearing it is fine.

(defparameter +login-attempts+ 5)
(defparameter +login-window-seconds+ 300)
(defvar *login-failures* (make-hash-table :test 'equal))
(defvar *login-failures-lock* (bordeaux-threads-2:make-lock :name "koya-login-failures"))

(defun login-locked-p (address)
  "True when ADDRESS has failed too often recently."
  (bordeaux-threads-2:with-lock-held (*login-failures-lock*)
    (let ((entry (gethash address *login-failures*)))
      (and entry
           (>= (car entry) +login-attempts+)
           (< (- (get-universal-time) (cdr entry)) +login-window-seconds+)))))

(defun note-login-failure (address)
  (bordeaux-threads-2:with-lock-held (*login-failures-lock*)
    (let ((entry (gethash address *login-failures*))
          (now (get-universal-time)))
      (setf (gethash address *login-failures*)
            (if (and entry (< (- now (cdr entry)) +login-window-seconds+))
                (cons (1+ (car entry)) now)
                (cons 1 now))))))

(defun clear-login-failures (address)
  (bordeaux-threads-2:with-lock-held (*login-failures-lock*)
    (remhash address *login-failures*)))

(defun session-login (secret &optional code)
  "Mark the current session as the owner when SECRET is right and, with TOTP
enabled, CODE is the current one-time code. Returns T on success, :code when only
the code is wrong or missing, NIL otherwise. The secret is checked first so a
wrong secret never learns whether a code would have been accepted."
  (cond ((not (secure-string= secret (koya-secret))) nil)
        ((and (totp-enabled-p) (not (totp-code-valid-p code))) :code)
        (t (setf (gethash "owner" (ningle:context :session)) t)
           t)))

(defun session-logout ()
  (remhash "owner" (ningle:context :session)))

(defun owner-env-p (env)
  (let ((session (getf env :lack.session)))
    (or (and session (gethash "owner" session) t)
        (let ((token (bearer-token env)))
          (and token (secure-string= token (koya-secret)))))))

(defun cross-origin-write-p (env)
  "A state-changing request whose Origin/Referer does not match this server. The
session cookie would otherwise let a page on another site drive the admin API."
  (let ((headers (getf env :headers)))
    (and (member (getf env :request-method) '(:post :put :patch :delete))
         (not (origin-allowed-p (gethash "origin" headers) (gethash "referer" headers) (gethash "host" headers))))))

(defparameter *admin-auth-middleware*
  (lambda (app)
    (lambda (env)
      (cond ((not (owner-env-p env))
             (json-response 401 (error-object "unauthorized" "Owner authentication required")))
            ((cross-origin-write-p env)
             (json-response 403 (error-object "forbidden" "Cross-origin request rejected")))
            (t (funcall app env)))))
  "Lack middleware guarding the admin API: owner session or Bearer secret, and
no cross-origin writes.")

(defun require-api-key (space)
  "Signal 401/403 unless the request carries an API key valid for SPACE."
  (let* ((key (header "x-koya-api-key"))
         (key-space (space-for-api-key key)))
    (cond ((null key) (fail-api 401 "unauthorized" "X-KOYA-API-KEY header is required"))
          ((null key-space) (fail-api 401 "unauthorized" "Invalid API key"))
          ((string/= key-space space) (fail-api 403 "forbidden" "API key does not belong to this space"))
          (t t))))
