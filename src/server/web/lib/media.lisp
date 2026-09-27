(defpackage #:koya-server/web/lib/media
  (:use #:cl)
  (:import-from #:koya-server/usecases/media
                #:stored-file)
  (:import-from #:cl-ppcre
                #:scan-to-strings)
  (:export #:media-app))
(in-package #:koya-server/web/lib/media)

(defparameter +media-path-pattern+ "^([a-z][a-z0-9-]*)/([0-9A-Z]{26})\\.(png|jpg|gif|webp)\\z")

(defun media-file-response (rest)
  (multiple-value-bind (match groups) (scan-to-strings +media-path-pattern+ rest)
    (when match
      (multiple-value-bind (path mime) (stored-file (aref groups 0) (aref groups 1) (aref groups 2))
        (when path
          (list 200 (list :content-type mime :cache-control "public, max-age=31536000, immutable") path))))))

(defun media-app (env)
  (or (media-file-response (subseq (getf env :path-info) 1))
      (list 404 (list :content-type "text/plain") (list "Not Found"))))
