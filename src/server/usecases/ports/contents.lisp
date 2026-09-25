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

;;; Contents (domain/content) and the revisions their writes leave
;;; (domain/revision). The store keeps a content as it is handed one: what a
;;; write makes of a content is decided in the domain, and whether it is an
;;; event of its history in the use case, which records it.

(defgeneric get-content (id)
  (:documentation "The content ID in whichever space and model it is, or NIL."))

(defgeneric find-content (space model id))

(defgeneric find-contents-by-ids (space model ids)
  (:documentation "Hash of id -> content for those of IDS that are contents of MODEL in SPACE."))

(defgeneric find-object-content (space model)
  (:documentation "The content of the object model MODEL, or NIL."))

(defgeneric list-contents (space model schema-model query &key status only-status)
  (:documentation "(values CONTENTS TOTAL) for QUERY over MODEL's contents, SCHEMA-MODEL
being its definition. STATUS :published keeps the published contents and
filters their published data (the delivery API); :all keeps every content and
filters its draft data where it has one. ONLY-STATUS narrows to one of
+STATUSES+. A QUERY-LIMIT of NIL lists every content."))

(defgeneric count-contents (space model))

(defgeneric space-contents (space)
  (:documentation "Every content of SPACE, oldest first: what an export carries."))

(defgeneric insert-content (content)
  (:documentation "Store CONTENT, a new one, as it is: every field, its draft key and its
timestamps included."))

(defgeneric update-content (content)
  (:documentation "Store CONTENT, which is already there, as it is now."))

(defgeneric delete-content (id)
  (:documentation "Delete content ID and its revisions."))

(defgeneric unique-value-taken-p (space model field value &key exclude-id)
  (:documentation "True when another content of MODEL already uses VALUE for FIELD (in draft or published data)."))

(defgeneric contents-mentioning (space needle &key exclude-id)
  (:documentation "The contents of SPACE, but for EXCLUDE-ID, whose published or draft JSON holds
the string NEEDLE anywhere: every content that can refer to it, and possibly
some that do not (NEEDLE may appear in any field, and _ in it matches any
character). What they refer to is domain/references's to say."))

(defgeneric record-revision (content-id event data &key by created-at)
  (:documentation "Append what EVENT left content CONTENT-ID with, written by BY. CREATED-AT
is now unless the revision was written elsewhere: an import brings a content's
history along, oldest first, so it keeps its order."))

(defgeneric list-revisions (content-id &key published-only limit offset)
  (:documentation "Newest first. PUBLISHED-ONLY keeps the publishes: the versions that were live."))

(defgeneric count-revisions (content-id &key published-only))

(defgeneric find-revision (content-id id))

(defgeneric content-history (content-id)
  (:documentation "Every revision of CONTENT-ID, oldest first."))
