(defpackage #:koya-server/usecases/auth
  (:use #:cl)
  (:import-from #:ironclad
                #:constant-time-equal)
  (:import-from #:babel
                #:string-to-octets)
  (:import-from #:bordeaux-threads-2)
  (:import-from #:koya-server/usecases/ports/config
                #:owner-secret)
  (:import-from #:koya-server/usecases/settings
                #:totp-enabled-p #:totp-code-valid-p)
  (:import-from #:koya-server/usecases/ports/sessions
                #:make-session-store #:+session-seconds+)
  (:export #:secure-string=
           #:check-login
           #:attempt-login
           #:login-locked-p
           #:note-login-failure
           #:clear-login-failures
           #:make-session-store
           #:+session-seconds+))
(in-package #:koya-server/usecases/auth)

(defun secure-string= (a b)
  (and (stringp a) (stringp b)
       (= (length a) (length b))
       (constant-time-equal (string-to-octets a :encoding :utf-8) (string-to-octets b :encoding :utf-8))))

(defun check-login (secret &optional code)
  (cond ((not (secure-string= secret (owner-secret))) nil)
        ((and (totp-enabled-p) (not (totp-code-valid-p code))) :code)
        (t t)))

(defparameter +login-attempts+ 5)
(defparameter +login-window-seconds+ 300)
(defvar *login-failures* (make-hash-table :test 'equal))
(defvar *login-failures-lock* (bordeaux-threads-2:make-lock :name "koya-login-failures"))

(defun login-locked-p (address)
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

(defun attempt-login (address secret &optional code)
  (cond ((login-locked-p address) :locked)
        ((eq (check-login secret code) t) (clear-login-failures address) t)
        (t (note-login-failure address) nil)))
