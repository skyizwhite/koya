(defpackage #:koya-server/usecases/auth
  (:use #:cl)
  (:import-from #:ironclad
                #:constant-time-equal)
  (:import-from #:babel
                #:string-to-octets)
  (:import-from #:koya-server/usecases/ports/config
                #:owner-secret)
  (:import-from #:koya-server/usecases/settings
                #:totp-enabled-p #:totp-code-valid-p #:wrong-codes #:count-wrong-code)
  (:import-from #:koya-server/usecases/ports/sessions
                #:make-session-store #:delete-sessions #:+session-seconds+)
  (:import-from #:koya-server/domain/totp #:unix-now)
  (:export #:secure-string=
           #:+min-secret-length+
           #:owner-secret-long-enough-p
           #:check-login
           #:end-other-sessions
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

(defparameter +wrong-codes-per-step+ 5)

(defun check-login (secret code &key (time (unix-now)))
  (cond ((not (owner-secret-long-enough-p)) :short-secret)
        ((and (totp-enabled-p) (>= (wrong-codes time) +wrong-codes-per-step+)) :too-many-codes)
        ((not (secure-string= secret (owner-secret))) nil)
        ((not (totp-enabled-p)) t)
        ((totp-code-valid-p code :time time) t)
        (t (count-wrong-code time) :code)))

(defun end-other-sessions (session-id)
  (delete-sessions :except session-id))
