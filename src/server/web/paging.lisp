(defpackage #:koya-server/web/paging
  (:use #:cl)
  (:import-from #:koya-server/web/http
                #:param)
  (:export #:+page-size+
           #:page-number
           #:last-page
           #:page-offset))
(in-package #:koya-server/web/paging)

(defparameter +page-size+ 20)

(defun page-number (params)
  (max 1 (or (ignore-errors (parse-integer (or (param params "page") "1"))) 1)))

(defun last-page (total &optional (size +page-size+))
  (max 1 (ceiling total size)))

(defun page-offset (page &optional (size +page-size+))
  (* (1- page) size))
