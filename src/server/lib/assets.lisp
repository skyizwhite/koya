(defpackage #:koya-server/lib/assets
  (:use #:cl)
  (:export #:asset-url
           #:asset-version
           #:refresh-asset-version))
(in-package #:koya-server/lib/assets)

;;; Static files under assets/ are served with a one-year immutable cache, so
;;; their URLs carry a version that changes whenever any asset file does. The
;;; version is the newest write time under assets/, taken when this file loads
;;; (a deploy loads a fresh image) and on REFRESH-ASSET-VERSION.

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
  "URL of assets/PATH with the cache-busting version, e.g. /assets/style/dist.css?v=..."
  (format nil "/assets/~a?v=~a" path (asset-version)))
