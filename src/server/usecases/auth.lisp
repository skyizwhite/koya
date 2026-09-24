(defpackage #:koya-server/usecases/auth
  (:use #:cl)
  (:import-from #:ironclad
                #:constant-time-equal)
  (:import-from #:babel
                #:string-to-octets)
  (:import-from #:bordeaux-threads-2)
  (:import-from #:koya-server/usecases/ports/config
                #:owner-secret)
  (:import-from #:koya-server/usecases/settings/two-factor
                #:totp-enabled-p #:totp-code-valid-p)
  (:import-from #:koya-server/usecases/ports/sessions
                #:make-session-store #:purge-expired-sessions #:+session-seconds+)
  (:export #:secure-string=
           #:check-login
           #:login-locked-p
           #:note-login-failure
           #:clear-login-failures
           #:make-session-store
           #:purge-expired-sessions
           #:+session-seconds+))
(in-package #:koya-server/usecases/auth)

;;; The owner logs in with the owner secret and, when it is on, the code of the
;;; second factor. The login is then kept in a session, in the store
;;; MAKE-SESSION-STORE makes.

(defun secure-string= (a b)
  (and (stringp a) (stringp b)
       (= (length a) (length b))
       (constant-time-equal (string-to-octets a :encoding :utf-8) (string-to-octets b :encoding :utf-8))))

(defun check-login (secret &optional code)
  "T when SECRET is the owner secret and, with two-factor on, CODE is the current
one-time code; :CODE when only the code is wrong or missing; NIL otherwise. The
secret is checked first so a wrong secret never learns whether a code would
have been accepted."
  (cond ((not (secure-string= secret (owner-secret))) nil)
        ((and (totp-enabled-p) (not (totp-code-valid-p code))) :code)
        (t t)))

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
