(defpackage #:koya-server/lib/media-store
  (:use #:cl)
  (:import-from #:koya-server/lib/env
                #:media-dir #:base-url)
  (:import-from #:koya-server/lib/image
                #:sniff-image #:image-extension #:+image-types+)
  (:import-from #:koya-server/lib/http
                #:fail-api)
  (:import-from #:koya-server/db/media
                #:insert-media #:find-media #:delete-media
                #:media-id #:media-space #:media-filename #:media-mime #:media-size
                #:media-width #:media-height #:media-alt #:media-created-at)
  (:import-from #:koya/core/json
                #:jobject #:json-null)
  (:import-from #:cl-ppcre
                #:scan-to-strings)
  (:export #:*media-middleware*
           #:store-upload
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
    ;; the file first: a failed write (disk full) must not leave a row whose URL 404s
    (let* ((id (koya/core/ulid:make-ulid))
           (path (merge-pathnames (format nil "~a/~a.~a" space id (image-extension mime))
                                  (uiop:ensure-directory-pathname (media-dir)))))
      (ensure-directories-exist path)
      (with-open-file (out path :direction :output :element-type '(unsigned-byte 8) :if-exists :supersede)
        (write-sequence bytes out))
      (handler-case
          (insert-media space :id id :filename (safe-filename filename) :mime mime :size (length bytes)
                              :width width :height height :alt alt)
        (error (e)
          (ignore-errors (delete-file path))
          (error e))))))

(defun remove-media (media)
  "Delete the row and the file. A missing file is not an error."
  (delete-media (media-space media) (media-id media))
  (let ((path (media-path media)))
    (when (probe-file path) (delete-file path))))

;;; --- Serving ------------------------------------------------------------------

(defparameter +media-path-pattern+ "^([a-z][a-z0-9-]*)/([0-9A-Z]{26})\\.(png|jpg|gif|webp)\\z"
  "space/id.ext under /media/: only shapes STORE-UPLOAD produces, so no traversal.")

(defun media-file-response (rest)
  "Lack response for /media/REST, or NIL when REST is not a media path or the file is absent."
  (multiple-value-bind (match groups) (scan-to-strings +media-path-pattern+ rest)
    (when match
      (let* ((mime (car (find (aref groups 2) +image-types+ :key #'cdr :test #'string=)))
             (path (merge-pathnames (format nil "~a/~a.~a" (aref groups 0) (aref groups 1) (aref groups 2))
                                    (uiop:ensure-directory-pathname (media-dir)))))
        (when (probe-file path)
          ;; ids are never reused, so a URL always names the same bytes
          (list 200 (list :content-type mime :cache-control "public, max-age=31536000, immutable") path))))))

(defparameter *media-middleware*
  (lambda (app)
    (lambda (env)
      (let ((path (getf env :path-info)))
        (if (and (> (length path) 7) (string= "/media/" path :end2 7))
            (or (media-file-response (subseq path 7))
                (list 404 (list :content-type "text/plain") (list "Not Found")))
            (funcall app env)))))
  "Serves uploaded files from KOYA_MEDIA_DIR (read per request) under /media/.")
