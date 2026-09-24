(defpackage #:koya-server/usecases/media/library
  (:use #:cl)
  (:import-from #:koya-server/domain/errors
                #:fail #:koya-error #:koya-error-message #:conflict #:rejected #:too-large)
  (:import-from #:koya-server/domain/image
                #:sniff-image)
  (:import-from #:koya-server/domain/media
                #:media-id #:media-space #:media-filename #:media-mime #:safe-filename
                #:+max-upload-bytes+)
  (:import-from #:koya-server/usecases/ports/media
                #:insert-media #:delete-media #:media-references #:find-media #:list-media
                #:count-media #:update-media #:space-media #:media-reference-counts
                #:write-media-file #:delete-media-file #:delete-space-media-files)
  (:import-from #:koya/core/ulid
                #:make-ulid)
  (:export #:store-upload
           #:store-uploads
           #:remove-media
           #:remove-each
           #:remove-space-media
           #:find-media
           #:list-media
           #:count-media
           #:update-media
           #:space-media
           #:media-references
           #:media-reference-counts))
(in-package #:koya-server/usecases/media/library)

;;; A space's library: a file is stored with its metadata, and taken away only
;;; while nothing uses it.

(defun store-upload (space bytes &key filename (alt ""))
  "Accept BYTES as a new media of SPACE: sniff the type, write the file, insert the
row. Signals REJECTED or TOO-LARGE for data the library does not take."
  (when (zerop (length bytes)) (fail 'rejected "The uploaded file is empty" :code "empty_file"))
  (when (> (length bytes) +max-upload-bytes+)
    (fail 'too-large (format nil "Files are limited to ~a MB" (floor +max-upload-bytes+ (* 1024 1024)))))
  (multiple-value-bind (mime width height) (sniff-image bytes)
    (unless mime (fail 'rejected "Only PNG, JPEG, GIF and WebP images are accepted" :code "unsupported_type"))
    ;; the file first: a failed write (disk full) must not leave a row whose URL 404s
    (let ((id (make-ulid)))
      (write-media-file space id mime bytes)
      (handler-case
          (insert-media space :id id :filename (safe-filename filename) :mime mime :size (length bytes)
                              :width width :height height :alt alt)
        (error (e)
          (ignore-errors (delete-media-file space id mime))
          (error e))))))

(defun store-uploads (space files)
  "Store each of FILES, each a list (octets filename). Signals for the first that
is refused; the ones before it are kept."
  (dolist (file files (length files))
    (store-upload space (first file) :filename (second file))))

(defun remove-media (media)
  "Delete the row and the file. A missing file is not an error; a file some
content still uses is: it stays, and a CONFLICT coded in_use names the count."
  (let ((references (media-references (media-space media) (media-id media))))
    (when (plusp references)
      (fail 'conflict (format nil "~a is used by ~a content~:p; remove it from them first"
                              (media-filename media) references)
            :code "in_use")))
  (delete-media (media-space media) (media-id media))
  (delete-media-file (media-space media) (media-id media) (media-mime media)))

(defun remove-each (space ids)
  "Remove each of IDS: a file in use is refused, the rest still go.
Returns (values DONE FAILED FIRST-MESSAGE)."
  (let ((done 0) (failed 0) (message nil))
    (dolist (id ids (values done failed message))
      (handler-case
          (let ((media (find-media space id)))
            (cond ((null media)
                   (incf failed)
                   (unless message (setf message "one was gone already")))
                  (t (remove-media media) (incf done))))
        ;; every condition, not only the library's own: a file that will not
        ;; leave the disk must not take the selection down with it
        (koya-error (e)
          (incf failed)
          (unless message (setf message (koya-error-message e))))
        (error (e)
          (incf failed)
          (unless message (setf message (princ-to-string e))))))))

(defun remove-space-media (space)
  "Delete every file of SPACE. Called when the space itself is deleted, after the
rows have gone with it; nothing is left to reference them, so nothing is checked."
  (delete-space-media-files space))
