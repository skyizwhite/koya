(defpackage #:koya-server/usecases/ports/archives
  (:use #:cl)
  (:export #:write-archive
           #:create-upload
           #:upload-size
           #:append-to-upload
           #:delete-upload
           #:call-with-upload
           #:archive-entry-size
           #:archive-entry-bytes
           #:purge-stale-archives))
(in-package #:koya-server/usecases/ports/archives)

;;; Space archives as files: one written to be sent, and one collected piece by
;;; piece as it is uploaded, then read. Neither is ever held in memory whole.

(defgeneric write-archive (files)
  (:documentation "Write a zip holding FILES, each (name . source), to a new file and return
its pathname; the caller deletes it once it is sent. A source is octets, or a
media, whose file is copied from the library. Images are stored as they are:
they are compressed already."))

(defgeneric create-upload ()
  (:documentation "Start collecting an uploaded archive. Returns the id it goes by."))

(defgeneric upload-size (id)
  (:documentation "How many bytes of upload ID have arrived, or NIL when there is no such upload."))

(defgeneric append-to-upload (id octets)
  (:documentation "Add OCTETS to the end of upload ID."))

(defgeneric delete-upload (id))

(defgeneric call-with-upload (id function)
  (:documentation "Call FUNCTION with the archive upload ID holds, to read with
ARCHIVE-ENTRY-SIZE and ARCHIVE-ENTRY-BYTES. Signals INVALID-INPUT when it is no
zip."))

(defgeneric archive-entry-size (archive name)
  (:documentation "The size of the file NAME in ARCHIVE once unpacked, or NIL when it holds none."))

(defgeneric archive-entry-bytes (archive name)
  (:documentation "The file NAME in ARCHIVE, unpacked, or NIL when it holds none."))

(defgeneric purge-stale-archives ()
  (:documentation "Delete what an export or an upload left behind a day or more ago: a send
that broke off, an import given up halfway."))
