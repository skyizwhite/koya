(defpackage #:koya-server/usecases/ports/archives
  (:use #:cl)
  (:export #:write-archive
           #:create-upload
           #:upload-size
           #:append-to-upload
           #:delete-upload
           #:call-with-upload
           #:archive-document
           #:archive-entry-size
           #:archive-entry-bytes
           #:purge-stale-archives))
(in-package #:koya-server/usecases/ports/archives)

(defgeneric write-archive (document media))

(defgeneric create-upload ())

(defgeneric upload-size (id))

(defgeneric append-to-upload (id octets))

(defgeneric delete-upload (id))

(defgeneric call-with-upload (id function))

(defgeneric archive-document (archive))

(defgeneric archive-entry-size (archive name))

(defgeneric archive-entry-bytes (archive name limit))

(defgeneric purge-stale-archives ())
