(defpackage #:koya-server/domain/media
  (:use #:cl)
  (:import-from #:koya-server/domain/image
                #:image-extension)
  (:export #:media #:make-media
           #:media-id #:media-space #:media-filename #:media-mime #:media-size
           #:media-width #:media-height #:media-alt #:media-created-at
           #:media-file-name
           #:safe-filename
           #:+max-upload-bytes+))
(in-package #:koya-server/domain/media)

;;; A file of a space's library: its metadata. The bytes are kept apart from it,
;;; under the name MEDIA-FILE-NAME gives them.

(defstruct media
  id space filename mime size width height alt created-at)

(defparameter +max-upload-bytes+ (* 20 1024 1024))

(defun media-file-name (media)
  "id.ext: the file's name, and the last part of its URL. Ids are never reused,
so the name always stands for the same bytes."
  (format nil "~a.~a" (media-id media) (image-extension (media-mime media))))

(defun safe-filename (name)
  "The base name of an uploaded file, without any directory part, or a default."
  (let* ((name (or name ""))
         (base (subseq name (1+ (or (position-if (lambda (c) (member c '(#\/ #\\))) name :from-end t) -1))))
         (base (string-trim " " base)))
    (if (plusp (length base)) base "upload")))
