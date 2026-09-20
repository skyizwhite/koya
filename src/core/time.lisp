(defpackage #:koya/core/time
  (:use #:cl)
  (:import-from #:local-time
                #:now
                #:format-timestring
                #:parse-timestring
                #:+utc-zone+)
  (:export #:now-iso
           #:format-iso
           #:parse-iso))
(in-package #:koya/core/time)

;;; All timestamps on the wire and in the database are ISO 8601 in UTC with
;;; millisecond precision, e.g. 2026-09-20T05:04:03.123Z.

(defparameter +iso-format+
  '((:year 4) #\- (:month 2) #\- (:day 2) #\T (:hour 2) #\: (:min 2) #\: (:sec 2) #\. (:msec 3) #\Z))

(defun format-iso (timestamp)
  (format-timestring nil timestamp :format +iso-format+ :timezone +utc-zone+))

(defun now-iso ()
  (format-iso (now)))

(defun parse-iso (string)
  "Parse an ISO 8601 string into a local-time timestamp, or NIL when invalid
(including calendar-invalid dates, which local-time signals on)."
  (and (stringp string)
       (handler-case (parse-timestring string :fail-on-error nil)
         (error () nil))))
