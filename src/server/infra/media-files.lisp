(defpackage #:koya-server/infra/media-files
  (:use #:cl)
  (:import-from #:koya-server/infra/env
                #:media-dir)
  (:import-from #:koya-server/domain/image
                #:image-extension)
  (:import-from #:koya-server/usecases/ports/media
                #:media-file-path #:write-media-file #:delete-media-file #:delete-space-media-files))
(in-package #:koya-server/infra/media-files)

;;; The files of the media library, on disk at {KOYA_MEDIA_DIR}/{space}/{id}.{ext}.
;;; KOYA_MEDIA_DIR is read on every call.

(defun media-root ()
  (uiop:ensure-directory-pathname (media-dir)))

(defun media-file-path (space id mime)
  (merge-pathnames (format nil "~a/~a.~a" space id (image-extension mime)) (media-root)))

(defun write-media-file (space id mime bytes)
  "Write BYTES as the file of media ID. Returns its path."
  (let ((path (media-file-path space id mime)))
    (ensure-directories-exist path)
    (with-open-file (out path :direction :output :element-type '(unsigned-byte 8) :if-exists :supersede)
      (write-sequence bytes out))
    path))

(defun delete-media-file (space id mime)
  "Delete the file of media ID. A file that is not there is not an error."
  (let ((path (media-file-path space id mime)))
    (when (probe-file path) (delete-file path))))

(defun delete-space-media-files (space)
  "Delete every file of SPACE."
  (let ((directory (merge-pathnames (format nil "~a/" space) (media-root))))
    (when (uiop:directory-exists-p directory)
      (uiop:delete-directory-tree directory :validate t))))
