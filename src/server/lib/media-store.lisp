(defpackage #:koya-server/lib/media-store
  (:use #:cl)
  (:import-from #:koya-server/lib/env
                #:media-dir #:base-url)
  (:import-from #:koya-server/lib/image
                #:sniff-image #:image-extension)
  (:import-from #:koya-server/lib/http
                #:fail-api)
  (:import-from #:koya-server/db/media
                #:insert-media #:find-media #:delete-media
                #:media-id #:media-space #:media-filename #:media-mime #:media-size
                #:media-width #:media-height #:media-alt #:media-created-at)
  (:import-from #:koya/core/json
                #:jobject #:json-null)
  (:export #:store-upload
           #:remove-media
           #:media-path
           #:media-url
           #:media->jobject
           #:+max-upload-bytes+))
(in-package #:koya-server/lib/media-store)

;;; Files on disk plus the metadata row. Layout: {KOYA_MEDIA_DIR}/{space}/{id}.{ext},
;;; served by the app itself at /media/{space}/{id}.{ext}.

(defparameter +max-upload-bytes+ (* 20 1024 1024))

(defun media-file-name (media)
  (format nil "~a.~a" (media-id media) (image-extension (media-mime media))))

(defun media-path (media)
  (merge-pathnames (format nil "~a/~a" (media-space media) (media-file-name media))
                   (uiop:ensure-directory-pathname (media-dir))))

(defun media-url (media &key (absolute t))
  (let ((path (format nil "/media/~a/~a" (media-space media) (media-file-name media))))
    (if absolute
        (concatenate 'string (string-right-trim "/" (base-url)) path)
        path)))

(defun media->jobject (media)
  (jobject "id" (media-id media)
           "url" (media-url media)
           "filename" (media-filename media)
           "mime" (media-mime media)
           "size" (media-size media)
           "width" (or (media-width media) json-null)
           "height" (or (media-height media) json-null)
           "alt" (media-alt media)
           "createdAt" (media-created-at media)))

(defun safe-filename (name)
  "The base name of an uploaded file, without any directory part, or a default."
  (let* ((name (or name ""))
         (base (subseq name (1+ (or (position-if (lambda (c) (member c '(#\/ #\\))) name :from-end t) -1))))
         (base (string-trim " " base)))
    (if (plusp (length base)) base "upload")))

(defun store-upload (space bytes &key filename (alt ""))
  "Accept BYTES as a new media of SPACE: sniff the type, write the file, insert the
row. Signals a 4xx api-error for unsupported or oversized data."
  (when (zerop (length bytes)) (fail-api 422 "empty_file" "The uploaded file is empty"))
  (when (> (length bytes) +max-upload-bytes+)
    (fail-api 413 "too_large" (format nil "Files are limited to ~a MB" (floor +max-upload-bytes+ (* 1024 1024)))))
  (multiple-value-bind (mime width height) (sniff-image bytes)
    (unless mime (fail-api 422 "unsupported_type" "Only PNG, JPEG, GIF and WebP images are accepted"))
    (let ((media (insert-media space :filename (safe-filename filename) :mime mime :size (length bytes)
                                     :width width :height height :alt alt)))
      (let ((path (media-path media)))
        (ensure-directories-exist path)
        (with-open-file (out path :direction :output :element-type '(unsigned-byte 8) :if-exists :supersede)
          (write-sequence bytes out)))
      media)))

(defun remove-media (media)
  "Delete the row and the file. A missing file is not an error."
  (delete-media (media-space media) (media-id media))
  (let ((path (media-path media)))
    (when (probe-file path) (delete-file path))))
