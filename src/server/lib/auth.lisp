(defpackage #:koya-server/lib/auth
  (:use #:cl)
  (:import-from #:koya-server/lib/env
                #:koya-secret)
  (:import-from #:koya-server/lib/http
                #:fail-api #:header #:json-response #:error-object)
  (:import-from #:koya-server/db/api-keys
                #:space-for-api-key)
  (:import-from #:ironclad
                #:constant-time-equal)
  (:import-from #:babel
                #:string-to-octets)
  (:export #:secure-string=
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

(defun session-login (secret)
  "Mark the current session as the owner when SECRET is right. Returns T on success."
  (when (secure-string= secret (koya-secret))
    (setf (gethash "owner" (ningle:context :session)) t)
    t))

(defun session-logout ()
  (remhash "owner" (ningle:context :session)))

(defun owner-env-p (env)
  (let ((session (getf env :lack.session)))
    (or (and session (gethash "owner" session) t)
        (let ((token (bearer-token env)))
          (and token (secure-string= token (koya-secret)))))))

(defparameter *admin-auth-middleware*
  (lambda (app)
    (lambda (env)
      (if (owner-env-p env)
          (funcall app env)
          (json-response 401 (error-object "unauthorized" "Owner authentication required")))))
  "Lack middleware guarding the admin API.")

(defun require-api-key (space)
  "Signal 401/403 unless the request carries an API key valid for SPACE."
  (let* ((key (or (header "x-koya-api-key") (header "x-microcms-api-key")))
         (key-space (space-for-api-key key)))
    (cond ((null key) (fail-api 401 "unauthorized" "X-KOYA-API-KEY header is required"))
          ((null key-space) (fail-api 401 "unauthorized" "Invalid API key"))
          ((string/= key-space space) (fail-api 403 "forbidden" "API key does not belong to this space"))
          (t t))))
