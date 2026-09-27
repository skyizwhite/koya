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

(defvar *repository-loaded* nil)
(defvar *repository-lock* (bordeaux-threads-2:make-lock :name "koya-timezones"))

(defun repository-path ()
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
  (cond ((not (stringp name)) nil)
        ((string-equal name "UTC") +utc-zone+)
        (t (ensure-repository)
           (and (plusp (repository-count)) (find-timezone-by-location-name name)))))

(defun timezone-name-p (name) (and (find-timezone name) t))

(defun timezone-names ()
  (ensure-repository)
  (let ((names '()))
    (maphash (lambda (name zone)
               (declare (ignore zone))
               (when (and (scan "^[A-Z][A-Za-z_+-]*(/[A-Za-z0-9_+-]+)*\\z" name)
                          (string/= name "UTC"))
                 (push name names)))
             local-time::*location-name->timezone*)
    (cons "UTC" (sort names #'string<))))

(defparameter +display-format+
  '((:year 4) #\- (:month 2) #\- (:day 2) #\Space (:hour 2) #\: (:min 2) #\Space :timezone))

(defparameter +input-format+
  '((:year 4) #\- (:month 2) #\- (:day 2) #\T (:hour 2) #\: (:min 2)))

(defun format-local (iso &key (timezone +utc-zone+))
  (let ((timestamp (parse-iso iso)))
    (if timestamp
        (format-timestring nil timestamp :format +display-format+ :timezone timezone)
        (or iso ""))))

(defun iso->local-input (iso &key (timezone +utc-zone+))
  (let ((timestamp (parse-iso iso)))
    (if timestamp
        (format-timestring nil timestamp :format +input-format+ :timezone timezone)
        (or iso ""))))

(defun local-input->iso (string &key (timezone +utc-zone+))
  (multiple-value-bind (match groups)
      (scan-to-strings "^(\\d{4})-(\\d{2})-(\\d{2})T(\\d{2}):(\\d{2})(?::(\\d{2}))?\\z" string)
    (if (null match)
        string
        (flet ((part (i) (parse-integer (or (aref groups i) "0"))))
          (handler-case
              (format-iso (encode-timestamp 0 (part 5) (part 4) (part 3) (part 2) (part 1) (part 0)
                                            :timezone timezone))
            (error () string))))))
