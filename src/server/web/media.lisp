(defpackage #:koya-server/web/media
  (:use #:cl)
  (:import-from #:koya-server/usecases/media/delivery
                #:stored-file)
  (:import-from #:cl-ppcre
                #:scan-to-strings)
  (:export #:media-app))
(in-package #:koya-server/web/media)

(defparameter +media-path-pattern+ "^([a-z][a-z0-9-]*)/([0-9A-Z]{26})\\.(png|jpg|gif|webp)\\z"
  "space/id.ext under /media/: only shapes an upload produces, so no traversal.")

(defun media-file-response (rest)
  "Lack response for /media/REST, or NIL when REST is not a media path or the file is absent."
  (multiple-value-bind (match groups) (scan-to-strings +media-path-pattern+ rest)
    (when match
      (multiple-value-bind (path mime) (stored-file (aref groups 0) (aref groups 1) (aref groups 2))
        (when path
          ;; ids are never reused, so a URL always names the same bytes
          (list 200 (list :content-type mime :cache-control "public, max-age=31536000, immutable") path))))))

(defun media-app (env)
  "Serves the media library's files, mounted at /media."
  ;; the mount hands over the path below /media, which starts with its /
  (or (media-file-response (subseq (getf env :path-info) 1))
      (list 404 (list :content-type "text/plain") (list "Not Found"))))
