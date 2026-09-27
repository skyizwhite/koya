(defpackage #:koya-server/web/assets
  (:use #:cl)
  (:import-from #:quri #:make-uri #:render-uri)
  (:export #:asset-url
           #:asset-version
           #:refresh-asset-version))
(in-package #:koya-server/web/assets)

(defvar *asset-version* nil)

(defun newest-write-date (directory)
  (let ((newest 0))
    (dolist (file (uiop:directory-files directory) newest)
      (setf newest (max newest (or (file-write-date file) 0))))
    (dolist (sub (uiop:subdirectories directory) newest)
      (setf newest (max newest (newest-write-date sub))))))

(defun refresh-asset-version ()
  (setf *asset-version*
        (let ((dir (uiop:ensure-directory-pathname "assets/")))
          (if (probe-file dir)
              (format nil "~36r" (newest-write-date dir))
              "0"))))

(defun asset-version ()
  (or *asset-version* (refresh-asset-version)))

(defun asset-url (path)
  (render-uri (make-uri :path (format nil "/assets/~a" path) :query `(("v" . ,(asset-version))))))
