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
                #:call-with-upload #:archive-document #:archive-entry-size #:archive-entry-bytes
                #:purge-stale-archives)
  (:import-from #:koya-core/json
                #:jobject #:jget #:json-array-p #:parse-json #:to-json)
  (:import-from #:koya-core/case
                #:jvalue->data #:data->jvalue #:data->jobject)
  (:import-from #:koya-core/schema-json
                #:schema->jobject #:jobject->schema #:forget-slug-options)
  (:import-from #:access
                #:access)
  (:import-from #:babel
                #:string-to-octets #:octets-to-string)
  (:import-from #:koya-core/ulid
                #:make-ulid)
  (:import-from #:cl-ppcre
                #:scan)
  (:import-from #:org.shirakumo.zippy
                #:zip-file #:zip-entry #:compress-zip #:open-zip-file #:entries #:file-name
                #:uncompressed-size #:decode-entry))
(in-package #:koya-server/infra/archives)

(defparameter +stale-seconds+ (* 24 3600))

(defun archive-file (name)
  (ensure-directories-exist (merge-pathnames name (archive-dir))))

(defparameter +archive-version+ 1)

(defparameter +max-document-bytes+ (* 100 1024 1024))

(defun version->jvalue (data)
  (if (eq data :null) 'null (data->jobject data)))

(defun content->jvalue (content)
  (let ((out (data->jvalue content)))
    (setf (gethash "published" out) (version->jvalue (access content :published :test #'eq))
          (gethash "draft" out) (version->jvalue (access content :draft :test #'eq))
          (gethash "revisions" out)
          (map 'vector (lambda (revision)
                         (let ((r (data->jvalue revision)))
                           (setf (gethash "data" r) (data->jobject (access revision :data :test #'eq)))
                           r))
               (access content :revisions :test #'eq)))
    out))

(defun document->json (document)
  (let ((out (jobject "koyaExport" +archive-version+)))
    (maphash (lambda (k v) (setf (gethash k out) v)) (data->jvalue document))
    (setf (gethash "schema" out) (schema->jobject (access document :schema :test #'eq))
          (gethash "contents" out) (map 'vector #'content->jvalue (access document :contents :test #'eq)))
    (to-json out)))

(defun without-slug-options (schema)
  (let ((models (and (hash-table-p schema) (jget schema "models"))))
    (when (json-array-p models)
      (map nil #'forget-slug-options models)))
  schema)

(defun json->document (json)
  (let ((document (handler-case (parse-json json)
                    (error () (fail 'invalid-input "space.json is not valid JSON")))))
    (unless (hash-table-p document) (fail 'invalid-input "space.json must be an object"))
    (unless (eql (jget document "koyaExport") +archive-version+)
      (fail 'invalid-input (format nil "Unsupported archive version ~s (expected ~a)"
                                   (jget document "koyaExport") +archive-version+)))
    (let ((schema (jobject->schema (without-slug-options (jget document "schema")))))
      (remhash "schema" document)
      (list* :schema schema (jvalue->data document)))))

(defmethod archive-document (archive)
  (let ((json (or (archive-entry-bytes archive "space.json" +max-document-bytes+)
                  (fail 'invalid-input "The archive has no space.json"))))
    (json->document (octets-to-string json :encoding :utf-8))))

(defmethod write-archive (document media)
  (let ((path (archive-file (format nil "export-~a.zip" (make-ulid))))
        (files (cons (cons "space.json" (string-to-octets (document->json document) :encoding :utf-8)) media)))
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
  entries)

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

(defun entry-bytes (entry name limit)
  (let ((size (uncompressed-size entry)))
    (unless (and (integerp size) (<= size limit))
      (fail 'invalid-input (format nil "~a in the archive is larger than ~a bytes" name limit)))
    (let ((bytes (make-array size :element-type '(unsigned-byte 8)))
          (filled 0))
      (flet ((lie () (fail 'invalid-input (format nil "~a in the archive is not the size its headers say" name))))
        (decode-entry (lambda (buffer start end)
                        (when (> (+ filled (- end start)) size) (lie))
                        (replace bytes buffer :start1 filled :start2 start :end2 end)
                        (incf filled (- end start))
                        end)
                      entry)
        (unless (= filled size) (lie)))
      bytes)))

(defmethod archive-entry-bytes (archive name limit)
  (let ((entry (gethash name (archive-entries archive))))
    (and entry (entry-bytes entry name limit))))

(defmethod purge-stale-archives ()
  (let ((directory (archive-dir))
        (before (- (get-universal-time) +stale-seconds+)))
    (when (uiop:directory-exists-p directory)
      (dolist (file (uiop:directory-files directory))
        (when (< (or (file-write-date file) 0) before)
          (uiop:delete-file-if-exists file))))))
