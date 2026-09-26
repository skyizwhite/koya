(defpackage #:koya-server/domain/timezone
  (:use #:cl)
  (:import-from #:local-time
                #:+utc-zone+ #:reread-timezone-repository #:find-timezone-by-location-name
                #:format-timestring #:encode-timestamp)
  (:import-from #:cl-ppcre
                #:scan #:scan-to-strings)
  (:import-from #:bordeaux-threads-2)
  (:import-from #:koya-core/time
                #:parse-iso #:format-iso)
  (:export #:find-timezone
           #:timezone-name-p
           #:timezone-names
           #:format-local
           #:iso->local-input
           #:local-input->iso))
(in-package #:koya-server/domain/timezone)

;;; Everything stored and served is UTC (see koya-core/time); a time is shown and
;;; typed in a zone named the IANA way (Asia/Tokyo). The zone database is the
;;; system's, read from /usr/share/zoneinfo on first use; without it only UTC is
;;; available.

(defvar *repository-loaded* nil)
(defvar *repository-lock* (bordeaux-threads-2:make-lock :name "koya-timezones"))

(defun repository-path ()
  ;; local-time's own default is the copy in its source tree, found through ASDF
  ;; when it loads: in the executable the Dockerfile saves, a directory of the
  ;; build stage that the image does not have
  (let ((system #p"/usr/share/zoneinfo/"))
    (if (probe-file system) system local-time::*default-timezone-repository-path*)))

(defun ensure-repository ()
  (unless *repository-loaded*
    (bordeaux-threads-2:with-lock-held (*repository-lock*)
      (unless *repository-loaded*
        (handler-case (reread-timezone-repository :timezone-repository (repository-path))
          (error (e) (format *error-output* "~&[koya] time zone database not loaded, UTC only: ~a~%" e)))
        (setf *repository-loaded* t)))))

(defun repository-count ()
  (hash-table-count local-time::*location-name->timezone*))

(defun find-timezone (name)
  "The local-time zone named NAME (an IANA name, or UTC), or NIL."
  (cond ((not (stringp name)) nil)
        ((string-equal name "UTC") +utc-zone+)
        (t (ensure-repository)
           ;; FIND-TIMEZONE-BY-LOCATION-NAME errors on an empty repository
           (and (plusp (repository-count)) (find-timezone-by-location-name name)))))

(defun timezone-name-p (name) (and (find-timezone name) t))

(defun timezone-names ()
  "The zone names the server can offer, UTC first, then IANA names sorted.
The repository also holds posix/ and right/ copies and files that are not zones
(posixrules, localtime): only Area/Location style names are kept."
  (ensure-repository)
  (let ((names '()))
    (maphash (lambda (name zone)
               (declare (ignore zone))
               (when (and (scan "^[A-Z][A-Za-z_+-]*(/[A-Za-z0-9_+-]+)*\\z" name)
                          (string/= name "UTC"))
                 (push name names)))
             local-time::*location-name->timezone*)
    (cons "UTC" (sort names #'string<))))

;;; --- Formatting -----------------------------------------------------------------

(defparameter +display-format+
  '((:year 4) #\- (:month 2) #\- (:day 2) #\Space (:hour 2) #\: (:min 2) #\Space :timezone)
  "2026-09-20 14:04 JST: what the lists and the editor's metadata show.")

(defparameter +input-format+
  '((:year 4) #\- (:month 2) #\- (:day 2) #\T (:hour 2) #\: (:min 2))
  "2026-09-20T14:04: the value of an <input type=datetime-local>.")

(defun format-local (iso &key (timezone +utc-zone+))
  "ISO (UTC, as stored) shown in TIMEZONE with its abbreviation. Anything that is
not a timestamp is returned as it is, so a bad value is at least visible."
  (let ((timestamp (parse-iso iso)))
    (if timestamp
        (format-timestring nil timestamp :format +display-format+ :timezone timezone)
        (or iso ""))))

(defun iso->local-input (iso &key (timezone +utc-zone+))
  "ISO (UTC) as the value of a datetime-local input in TIMEZONE."
  (let ((timestamp (parse-iso iso)))
    (if timestamp
        (format-timestring nil timestamp :format +input-format+ :timezone timezone)
        (or iso ""))))

(defun local-input->iso (string &key (timezone +utc-zone+))
  "2026-09-20T14:04 (or with :SS) typed in TIMEZONE -> the stored UTC form,
2026-09-20T05:04:00.000Z. Any other STRING comes back unchanged for validation to reject."
  (multiple-value-bind (match groups)
      (scan-to-strings "^(\\d{4})-(\\d{2})-(\\d{2})T(\\d{2}):(\\d{2})(?::(\\d{2}))?\\z" string)
    (if (null match)
        string
        (flet ((part (i) (parse-integer (or (aref groups i) "0"))))
          (handler-case
              (format-iso (encode-timestamp 0 (part 5) (part 4) (part 3) (part 2) (part 1) (part 0)
                                            :timezone timezone))
            (error () string))))))
