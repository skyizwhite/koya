(defpackage #:koya-server/infra/archives
  (:use #:cl)
  (:import-from #:koya-server/infra/env
                #:archive-dir)
  (:import-from #:koya-server/domain/errors
                #:fail #:invalid-input)
  (:import-from #:koya-server/domain/media
                #:media #:media-space #:media-id #:media-mime)
  (:import-from #:koya-server/usecases/ports/media
                #:media-file-path)
  (:import-from #:koya-server/usecases/ports/archives
                #:write-archive #:create-upload #:upload-size #:append-to-upload #:delete-upload
                #:call-with-upload #:archive-entry-size #:archive-entry-bytes #:purge-stale-archives)
  (:import-from #:koya/core/ulid
                #:make-ulid)
  (:import-from #:cl-ppcre
                #:scan)
  (:import-from #:org.shirakumo.zippy
                #:zip-file #:zip-entry #:compress-zip #:open-zip-file #:entries #:file-name
                #:uncompressed-size #:entry-to-vector))
(in-package #:koya-server/infra/archives)

;;; Archives are files in ARCHIVE-DIR: export-<ulid>.zip while one is being sent,
;;; <ulid>.upload while one is arriving. zippy copies an entry from its source
;;; and unpacks one on demand, a few kilobytes at a time, so neither side holds
;;; a space's files in memory.

(defparameter +stale-seconds+ (* 24 3600))

(defun archive-file (name)
  (ensure-directories-exist (merge-pathnames name (archive-dir))))

(defmethod write-archive (files)
  (let ((path (archive-file (format nil "export-~a.zip" (make-ulid)))))
    (compress-zip
     (make-instance 'zip-file
                    :entries (map 'vector
                                  (lambda (file)
                                    (destructuring-bind (name . source) file
                                      (if (typep source 'media)
                                          (make-instance 'zip-entry
                                                         :file-name name
                                                         :content (media-file-path (media-space source)
                                                                                   (media-id source)
                                                                                   (media-mime source))
                                                         :compression-method :store)
                                          (make-instance 'zip-entry :file-name name :content source))))
                                  files))
     path :if-exists :supersede)
    path))

(defun upload-file (id)
  "The file of upload ID, or NIL for an id no upload could have: it comes from the
request, and becomes a file name."
  (and (stringp id) (scan "^[0-9A-Z]{26}\\z" id)
       (merge-pathnames (format nil "~a.upload" id) (archive-dir))))

(defmethod create-upload ()
  (let ((id (make-ulid)))
    (with-open-file (out (archive-file (format nil "~a.upload" id))
                         :direction :output :element-type '(unsigned-byte 8) :if-exists :error))
    id))

(defmethod upload-size (id)
  (let ((path (upload-file id)))
    (and path (probe-file path)
         (with-open-file (in path :element-type '(unsigned-byte 8))
           (file-length in)))))

(defmethod append-to-upload (id octets)
  (with-open-file (out (upload-file id) :direction :output :element-type '(unsigned-byte 8)
                                        :if-exists :append :if-does-not-exist :error)
    (write-sequence octets out)))

(defmethod delete-upload (id)
  (let ((path (upload-file id)))
    (when path (uiop:delete-file-if-exists path))))

(defstruct (archive (:constructor make-archive (entries)))
  entries)                              ; name -> zippy entry

(defmethod call-with-upload (id function)
  (multiple-value-bind (zip streams)
      (handler-case (open-zip-file (upload-file id))
        (error () (fail 'invalid-input "This file is not a zip archive")))
    (unwind-protect
         (let ((entries (make-hash-table :test 'equal)))
           (loop :for entry :across (entries zip)
                 :do (setf (gethash (file-name entry) entries) entry))
           (funcall function (make-archive entries)))
      (mapc #'close streams))))

(defmethod archive-entry-size (archive name)
  (let ((entry (gethash name (archive-entries archive))))
    (and entry (uncompressed-size entry))))

(defmethod archive-entry-bytes (archive name)
  (let ((entry (gethash name (archive-entries archive))))
    (and entry (entry-to-vector entry))))

(defmethod purge-stale-archives ()
  (let ((directory (archive-dir))
        (before (- (get-universal-time) +stale-seconds+)))
    (when (uiop:directory-exists-p directory)
      (dolist (file (uiop:directory-files directory))
        (when (< (or (file-write-date file) 0) before)
          (uiop:delete-file-if-exists file))))))
