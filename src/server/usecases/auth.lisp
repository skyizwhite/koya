(defpackage #:koya-server/usecases/auth
  (:use #:cl)
  (:import-from #:ironclad
                #:constant-time-equal)
  (:import-from #:babel
                #:string-to-octets)
  (:import-from #:koya-server/usecases/ports/config
                #:owner-secret)
  (:import-from #:koya-server/usecases/settings
                #:totp-enabled-p #:totp-code-valid-p)
  (:import-from #:koya-server/usecases/ports/sessions
                #:make-session-store #:+session-seconds+)
  (:export #:secure-string=
           #:+min-secret-length+
           #:owner-secret-long-enough-p
           #:check-login
           #:make-session-store
           #:+session-seconds+))
(in-package #:koya-server/usecases/auth)

(defun secure-string= (a b)
  (and (stringp a) (stringp b)
       (= (length a) (length b))
       (constant-time-equal (string-to-octets a :encoding :utf-8) (string-to-octets b :encoding :utf-8))))

(defparameter +min-secret-length+ 32)

(defun owner-secret-long-enough-p ()
  (>= (length (owner-secret)) +min-secret-length+))

(defun check-login (secret &optional code)
  (cond ((not (owner-secret-long-enough-p)) :short-secret)
        ((not (secure-string= secret (owner-secret))) nil)
        ((and (totp-enabled-p) (not (totp-code-valid-p code))) :code)
        (t t)))
