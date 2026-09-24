(defpackage #:koya-server/web/presenters
  (:use #:cl)
  (:import-from #:koya/core/json #:jobject #:json-null)
  (:import-from #:koya-server/domain/content
                #:content-id #:content-status #:content-published #:content-draft
                #:content-draft-key #:content-created-at #:content-updated-at
                #:content-published-at #:content-revised-at)
  (:export #:admin-content->jobject))
(in-package #:koya-server/web/presenters)

;;; What the admin API answers with, where it is not the delivery shape
;;; (usecases/contents/delivery).

(defun copy-object (object)
  (let ((out (make-hash-table :test 'equal)))
    (maphash (lambda (k v) (setf (gethash k out) v)) object)
    out))

(defun admin-content->jobject (content)
  "A content with its status, both versions of its data and its metadata."
  (flet ((data (object) (and object (copy-object object))))
    (jobject "id" (content-id content)
             "status" (content-status content)
             "published" (or (data (content-published content)) json-null)
             "draft" (or (data (content-draft content)) json-null)
             "draftKey" (or (content-draft-key content) json-null)
             "createdAt" (content-created-at content)
             "updatedAt" (content-updated-at content)
             "publishedAt" (or (content-published-at content) json-null)
             "revisedAt" (or (content-revised-at content) json-null))))
