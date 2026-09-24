(defpackage #:koya-server/usecases/ports/contents
  (:use #:cl)
  (:export #:get-content
           #:find-content
           #:find-contents-by-ids
           #:find-object-content
           #:list-contents
           #:count-contents
           #:space-contents
           #:create-content
           #:save-draft
           #:publish-content
           #:unpublish-content
           #:discard-draft
           #:delete-content
           #:import-content
           #:ensure-draft-key
           #:unique-value-taken-p
           #:contents-mentioning
           #:list-revisions
           #:count-revisions
           #:find-revision
           #:content-history
           #:import-revision))
(in-package #:koya-server/usecases/ports/contents)

;;; Contents (domain/content) and the revision each write leaves
;;; (domain/revision). A write records its revision itself, naming whoever BY
;;; says.

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

(defgeneric create-content (space model data &key publish id created-at updated-at published-at revised-at by)
  (:documentation "Insert DATA as a new content. With PUBLISH it is published immediately,
otherwise saved as a draft. The system timestamps default to now; imports may
supply any of CREATED-AT, UPDATED-AT, PUBLISHED-AT and REVISED-AT (ISO 8601).
PUBLISHED-AT and REVISED-AT are only stored when publishing."))

(defgeneric save-draft (id data &key by)
  (:documentation "Replace the draft of content ID with DATA. A fresh draft key is issued each time,
so old preview links stop working."))

(defgeneric publish-content (id &optional data &key published-at by)
  (:documentation "Publish DATA (or the current draft, or re-publish the published data) and clear the draft.
PUBLISHED-AT overrides the publish date; otherwise the first publish date is kept."))

(defgeneric unpublish-content (id &key by)
  (:documentation "Take content ID off the delivery API, keeping its data as a draft."))

(defgeneric discard-draft (id &key by)
  (:documentation "Drop the draft of the published content ID, so it shows its published data
again. Not for a content that has never been published: there would be nothing
left."))

(defgeneric delete-content (id)
  (:documentation "Delete content ID and its revisions."))

(defgeneric import-content (content)
  (:documentation "Insert CONTENT as it is, every column included, and record no revision: the
importer brings the content's history along with it."))

(defgeneric ensure-draft-key (id)
  (:documentation "Return the draft key of content ID, generating one on first use."))

(defgeneric unique-value-taken-p (space model field value &key exclude-id)
  (:documentation "True when another content of MODEL already uses VALUE for FIELD (in draft or published data)."))

(defgeneric contents-mentioning (space needle &key exclude-id)
  (:documentation "The contents of SPACE, but for EXCLUDE-ID, whose published or draft JSON holds
the string NEEDLE anywhere: every content that can refer to it, and possibly
some that do not (NEEDLE may appear in any field, and _ in it matches any
character). What they refer to is domain/references's to say."))

(defgeneric list-revisions (content-id &key published-only limit offset)
  (:documentation "Newest first. PUBLISHED-ONLY keeps the publishes: the versions that were live."))

(defgeneric count-revisions (content-id &key published-only))

(defgeneric find-revision (content-id id))

(defgeneric content-history (content-id)
  (:documentation "Every revision of CONTENT-ID, oldest first."))

(defgeneric import-revision (content-id event data &key by created-at)
  (:documentation "Append a revision as it was written elsewhere. Imported oldest first, so the
ids keep the order they had."))
