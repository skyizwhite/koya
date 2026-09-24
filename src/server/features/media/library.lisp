(defpackage #:koya-server/features/media/library
  (:use #:cl)
  (:import-from #:koya-server/db/media
                #:find-media)
  (:import-from #:koya-server/lib/http
                #:api-error #:api-error-message)
  (:import-from #:koya-server/features/media/store
                #:store-upload #:remove-media)
  (:export #:store-uploads
           #:remove-each))
(in-package #:koya-server/features/media/library)

;;; What is done to several files of a space's library at once.

(defun store-uploads (space files)
  "Store each of FILES, as UPLOADED-FILES gives them. Signals API-ERROR for the
first that is refused; the ones before it are kept."
  (dolist (file files (length files))
    (store-upload space (first file) :filename (second file))))

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
        ;; every condition, not only the store's own: a file that will not
        ;; leave the disk must not take the selection down with it
        (api-error (e)
          (incf failed)
          (unless message (setf message (api-error-message e))))
        (error (e)
          (incf failed)
          (unless message (setf message (princ-to-string e))))))))
