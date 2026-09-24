(defpackage #:koya-server/features/spaces/lifecycle
  (:use #:cl)
  (:import-from #:koya-server/db/schema-store
                #:delete-space)
  (:import-from #:koya-server/features/media/store
                #:remove-space-media)
  (:export #:remove-space))
(in-package #:koya-server/features/spaces/lifecycle)

;;; A space is made by a row alone (db/schema-store); taking one away also takes
;;; what it keeps on disk.

(defun remove-space (name)
  ;; the rows go first: the cascade takes the media rows with the space, and
  ;; only then is there nothing left pointing at the files
  (delete-space name)
  (remove-space-media name))
