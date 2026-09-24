(defpackage #:koya-server/usecases/ports/media
  (:use #:cl)
  (:export #:insert-media
           #:find-media
           #:find-media-by-ids
           #:list-media
           #:space-media
           #:count-media
           #:update-media
           #:delete-media
           #:media-file-path
           #:write-media-file
           #:delete-media-file
           #:delete-space-media-files))
(in-package #:koya-server/usecases/ports/media)

;;; A space's library: the metadata of each file (domain/media), and the file
;;; itself, kept apart from it.

(defgeneric insert-media (space &key filename mime size width height alt id created-at))

(defgeneric find-media (space id))

(defgeneric find-media-by-ids (space ids)
  (:documentation "Hash of id -> media for those of IDS that are in SPACE's library."))

(defgeneric list-media (space &key search limit offset)
  (:documentation "Newest first. SEARCH matches the file name."))

(defgeneric space-media (space)
  (:documentation "Every media of SPACE, oldest first."))

(defgeneric count-media (space &key search))

(defgeneric update-media (space id &key alt))

(defgeneric delete-media (space id))

(defgeneric media-file-path (space id mime)
  (:documentation "Where the file of media ID is kept, whether or not it is there."))

(defgeneric write-media-file (space id mime bytes)
  (:documentation "Write BYTES as the file of media ID. Returns its path."))

(defgeneric delete-media-file (space id mime)
  (:documentation "Delete the file of media ID. A file that is not there is not an error."))

(defgeneric delete-space-media-files (space)
  (:documentation "Delete every file of SPACE."))
