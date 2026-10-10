(defpackage #:koya-server/web/lib/paging
  (:use #:cl)
  (:import-from #:koya-server/web/lib/http
                #:param)
  (:export #:+page-size+
           #:page-number
           #:last-page
           #:page-offset))
(in-package #:koya-server/web/lib/paging)

(defparameter +page-size+ 20)
(defparameter +max-page+ (expt 2 32))

(defun page-number (params)
  (let ((page (param params "page")))
    (min +max-page+ (max 1 (or (and (stringp page) (handler-case (parse-integer page) (parse-error () nil))) 1)))))

(defun last-page (total &optional (size +page-size+))
  (max 1 (ceiling total size)))

(defun page-offset (page &optional (size +page-size+))
  (* (1- page) size))
