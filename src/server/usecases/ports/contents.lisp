(defpackage #:koya-server/usecases/ports/contents
  (:use #:cl)
  (:export #:get-content
           #:find-content
           #:find-contents-by-ids
           #:find-contents-by-slug
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

(defgeneric get-content (space id))

(defgeneric find-content (space model id))

(defgeneric find-contents-by-ids (space model ids))

(defgeneric find-contents-by-slug (space model slug))

(defgeneric find-object-content (space model))

(defgeneric list-contents (space model schema-model query &key status only-status))

(defgeneric count-contents (space model))

(defgeneric space-contents (space))

(defgeneric insert-content (content &key published-slug draft-slug))

(defgeneric update-content (content &key published-slug draft-slug))

(defgeneric delete-content (space id))

(defgeneric unique-value-taken-p (space model field value &key exclude-id))

(defgeneric contents-mentioning (space needle &key exclude-id))

(defgeneric record-revision (space content-id event data &key by created-at))

(defgeneric list-revisions (space content-id &key published-only limit offset))

(defgeneric count-revisions (space content-id &key published-only))

(defgeneric find-revision (space content-id id))

(defgeneric content-history (space content-id))
