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
;;; itself, kept apart from it. See ports/store for what a port is.

(declaim (ftype function insert-media find-media find-media-by-ids list-media space-media
                count-media update-media delete-media
                media-file-path write-media-file delete-media-file delete-space-media-files))
