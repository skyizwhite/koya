(defpackage #:koya-server/usecases/ports/contents
  (:use #:cl)
  (:export #:get-content
           #:find-content
           #:find-contents-by-ids
           #:find-object-content
           #:list-contents
           #:count-contents
           #:space-contents
           #:insert-content
           #:update-content
           #:delete-content
           #:unique-value-taken-p
           #:contents-mentioning
           #:record-revision
           #:list-revisions
           #:count-revisions
           #:find-revision
           #:content-history))
(in-package #:koya-server/usecases/ports/contents)

(defgeneric get-content (id))

(defgeneric find-content (space model id))

(defgeneric find-contents-by-ids (space model ids))

(defgeneric find-object-content (space model))

(defgeneric list-contents (space model schema-model query &key status only-status))

(defgeneric count-contents (space model))

(defgeneric space-contents (space))

(defgeneric insert-content (content))

(defgeneric update-content (content))

(defgeneric delete-content (id))

(defgeneric unique-value-taken-p (space model field value &key exclude-id))

(defgeneric contents-mentioning (space needle &key exclude-id))

(defgeneric record-revision (content-id event data &key by created-at))

(defgeneric list-revisions (content-id &key published-only limit offset))

(defgeneric count-revisions (content-id &key published-only))

(defgeneric find-revision (content-id id))

(defgeneric content-history (content-id))
