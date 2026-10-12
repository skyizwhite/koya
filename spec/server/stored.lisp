(defpackage #:koya-spec/server/stored
  (:use #:cl)
  (:import-from #:koya-server/usecases/ports/contents #:space-contents)
  (:import-from #:koya-server/domain/content #:content-id)
  (:export #:stored-content))
(in-package #:koya-spec/server/stored)

(defun stored-content (space id)
  (find id (space-contents space) :key #'content-id :test #'equal))
