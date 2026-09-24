(defpackage #:koya-server/usecases/ports/sessions
  (:use #:cl)
  (:export #:make-session-store
           #:+session-seconds+))
(in-package #:koya-server/usecases/ports/sessions)

;;; Where the owner's session is kept between requests.

(defgeneric make-session-store ()
  (:documentation "A Lack session store that keeps sessions across restarts."))

(defparameter +session-seconds+ (* 24 3600)
  "How long a session lives, in the cookie and in the store. Using a session
slides both, so the owner is logged out only after a day away.")
