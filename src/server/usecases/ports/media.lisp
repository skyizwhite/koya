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
           #:media-file-exists-p
           #:write-media-file
           #:delete-media-file
           #:delete-space-media-files))
(in-package #:koya-server/usecases/ports/media)

(defgeneric insert-media (space &key filename mime size width height alt id created-at))

(defgeneric find-media (space id))

(defgeneric find-media-by-ids (space ids))

(defgeneric list-media (space &key search limit offset))

(defgeneric space-media (space))

(defgeneric count-media (space &key search))

(defgeneric update-media (space id &key alt))

(defgeneric delete-media (space id))

(defgeneric media-file-path (space id mime))

(defgeneric media-file-exists-p (space id mime))

(defgeneric write-media-file (space id mime bytes &key new))

(defgeneric delete-media-file (space id mime))

(defgeneric delete-space-media-files (space))
