(defpackage #:koya-core/time
  (:use #:cl)
  (:import-from #:local-time
                #:now
                #:timestamp+
                #:format-timestring
                #:parse-timestring
                #:+utc-zone+)
  (:import-from #:cl-ppcre
                #:regex-replace)
  (:export #:now-iso
           #:iso-from-now
           #:format-iso
           #:parse-iso))
(in-package #:koya-core/time)

(defparameter +iso-format+
  '((:year 4) #\- (:month 2) #\- (:day 2) #\T (:hour 2) #\: (:min 2) #\: (:sec 2) #\. (:msec 3) #\Z))

(defun format-iso (timestamp)
  "TIMESTAMP, a local-time timestamp, as koya stores and serves it: ISO 8601 in UTC
with milliseconds."
  (format-timestring nil timestamp :format +iso-format+ :timezone +utc-zone+))

(defun now-iso ()
  "The current time as FORMAT-ISO writes it."
  (format-iso (now)))

(defun iso-from-now (seconds)
  (format-iso (timestamp+ (now) seconds :sec)))

(defun parse-iso (string)
  "Parse an ISO 8601 string into a local-time timestamp, or NIL when invalid
(including calendar-invalid dates, which local-time signals on)."
  (and (stringp string)
       (handler-case (parse-timestring (regex-replace "(T\\d{2}:\\d{2})(?=Z|[+-]\\d{2}:\\d{2}$)" string "\\1:00")
                                       :fail-on-error nil)
         (error () nil))))
