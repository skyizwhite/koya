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

(defstruct media
  id space filename mime size width height alt created-at)

(defparameter +max-upload-bytes+ (* 20 1024 1024))

(defun media-file-name (media)
  (format nil "~a.~a" (media-id media) (image-extension (media-mime media))))

(defun safe-filename (name)
  (let* ((name (or name ""))
         (base (subseq name (1+ (or (position-if (lambda (c) (member c '(#\/ #\\))) name :from-end t) -1))))
         (base (string-trim " " base)))
    (if (plusp (length base)) base "upload")))
