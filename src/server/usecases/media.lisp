(defpackage #:koya-server/usecases/media
  (:use #:cl)
  (:import-from #:koya-server/domain/errors
                #:fail #:koya-error #:koya-error-message #:conflict #:rejected #:too-large)
  (:import-from #:koya-server/domain/image #:sniff-image #:strip-metadata #:+image-types+)
  (:import-from #:koya-server/domain/media
                #:media-id #:media-space #:media-filename #:media-mime #:safe-filename
                #:+max-upload-bytes+)
  (:import-from #:koya-server/usecases/ports/media
                #:insert-media #:delete-media #:find-media #:list-media #:count-media #:update-media
                #:space-media #:write-media-file #:delete-media-file #:delete-space-media-files
                #:media-file-path #:media-file-exists-p)
  (:import-from #:koya-server/domain/references #:media-fields #:mentioned-ids)
  (:import-from #:koya-server/usecases/ports/spaces #:load-schema)
  (:import-from #:koya-server/usecases/ports/contents #:contents-mentioning #:space-contents)
  (:import-from #:koya-core/ulid #:make-ulid)
  (:export #:store-upload
           #:store-uploads
           #:upload-limit-message
           #:remove-media
           #:remove-each
           #:remove-space-media
           #:find-media
           #:list-media
           #:count-media
           #:update-media
           #:space-media
           #:media-references
           #:media-reference-counts
           #:stored-file))
(in-package #:koya-server/usecases/media)

(defun media-reference-counts (space ids)
  (let ((counts (make-hash-table :test 'equal))
        (fields (media-fields (load-schema space))))
    (dolist (id ids) (setf (gethash id counts) 0))
    (when ids
      (dolist (content (space-contents space))
        (dolist (id (mentioned-ids content fields ids))
          (incf (gethash id counts)))))
    counts))

(defun media-references (space id)
  (let ((fields (media-fields (load-schema space))))
    (count-if (lambda (content) (mentioned-ids content fields (list id)))
              (contents-mentioning space id))))

(defun upload-limit-message ()
  (let ((mb (floor +max-upload-bytes+ (* 1024 1024))))
    (format nil "Images are limited to ~a MB each, and ~a MB per upload" mb mb)))

(defun store-upload (space bytes &key filename (alt ""))
  (when (zerop (length bytes)) (fail 'rejected "The uploaded file is empty" :code "empty_file"))
  (when (> (length bytes) +max-upload-bytes+)
    (fail 'too-large (upload-limit-message)))
  (multiple-value-bind (mime width height) (sniff-image bytes)
    (unless mime (fail 'rejected "Only PNG, JPEG, GIF and WebP images are accepted" :code "unsupported_type"))
    (let ((id (make-ulid))
          (bytes (strip-metadata bytes mime)))
      (write-media-file space id mime bytes)
      (handler-case
          (insert-media space :id id :filename (safe-filename filename) :mime mime :size (length bytes)
                              :width width :height height :alt alt)
        (error (e)
          (ignore-errors (delete-media-file space id mime))
          (error e))))))

(defun store-uploads (space files &key (alt ""))
  (when (> (reduce #'+ files :key (lambda (file) (length (first file)))) +max-upload-bytes+)
    (fail 'too-large (upload-limit-message)))
  (mapcar (lambda (file) (store-upload space (first file) :filename (second file) :alt alt)) files))

(defun remove-media (media)
  (let ((references (media-references (media-space media) (media-id media))))
    (when (plusp references)
      (fail 'conflict (format nil "~a is used by ~a content~:p; remove it from them first"
                              (media-filename media) references)
            :code "in_use")))
  (delete-media (media-space media) (media-id media))
  (delete-media-file (media-space media) (media-id media) (media-mime media)))

(defun remove-each (space ids)
  (let ((done 0) (failed 0) (message nil))
    (dolist (id ids (values done failed message))
      (handler-case
          (let ((media (find-media space id)))
            (cond ((null media)
                   (incf failed)
                   (unless message (setf message "one was gone already")))
                  (t (remove-media media) (incf done))))
        (koya-error (e)
          (incf failed)
          (unless message (setf message (koya-error-message e))))
        (error (e)
          (incf failed)
          (unless message (setf message (princ-to-string e))))))))

(defun remove-space-media (space)
  (delete-space-media-files space))

(defun stored-file (space id extension)
  (let ((mime (car (rassoc extension +image-types+ :test #'string=))))
    (when (and mime (media-file-exists-p space id mime))
      (values (media-file-path space id mime) mime))))
