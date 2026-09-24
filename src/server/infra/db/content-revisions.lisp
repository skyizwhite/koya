(defpackage #:koya-server/infra/db/content-revisions
  (:use #:cl)
  (:import-from #:koya-server/infra/db/connection #:exec #:fetch #:fetch-one #:col)
  (:import-from #:koya-server/domain/revision
                #:make-revision #:revision-data)
  (:import-from #:koya/core/time
                #:now-iso)
  (:import-from #:koya/core/json
                #:parse-json #:to-json #:json-equal)
  (:import-from #:koya-server/usecases/ports/contents
                #:list-revisions #:count-revisions #:find-revision #:content-history
                #:import-revision)
  (:export #:record-revision))
(in-package #:koya-server/infra/db/content-revisions)

;;; One row per write to a content (domain/revision). Rows go with their content
;;; (ON DELETE CASCADE) and are otherwise kept.

(defun row->revision (row)
  (make-revision :id (col row "id")
                 :content-id (col row "content_id")
                 :event (col row "event")
                 :data (parse-json (col row "data"))
                 :by (col row "written_by")
                 :created-at (col row "created_at")))

(defun latest-revision (content-id)
  (let ((row (fetch-one "SELECT * FROM content_revisions WHERE content_id = ? ORDER BY id DESC LIMIT 1"
                        content-id)))
    (and row (row->revision row))))

(defun record-revision (content-id event data &key (by ""))
  "Store DATA as what EVENT left content CONTENT-ID with. A draft save that
changes nothing against the newest revision records nothing."
  (unless (and (string= event "draft")
               (let ((latest (latest-revision content-id)))
                 (and latest (json-equal (revision-data latest) data))))
    (exec "INSERT INTO content_revisions (content_id, event, data, written_by, created_at) VALUES (?, ?, ?, ?, ?)"
          content-id event (to-json data) (or by "") (now-iso))))

(defun where (published-only)
  (format nil "content_id = ?~:[~; AND event = 'publish'~]" published-only))

(defun list-revisions (content-id &key published-only (limit 20) (offset 0))
  "Newest first. PUBLISHED-ONLY keeps the publishes: the versions that were live."
  (mapcar #'row->revision
          (fetch (format nil "SELECT * FROM content_revisions WHERE ~a ORDER BY id DESC LIMIT ? OFFSET ?"
                         (where published-only))
                 content-id limit offset)))

(defun count-revisions (content-id &key published-only)
  (col (fetch-one (format nil "SELECT COUNT(*) AS n FROM content_revisions WHERE ~a" (where published-only))
                  content-id)
       "n"))

(defun find-revision (content-id id)
  (let ((row (fetch-one "SELECT * FROM content_revisions WHERE content_id = ? AND id = ?" content-id id)))
    (and row (row->revision row))))

(defun content-history (content-id)
  "Every revision of CONTENT-ID, oldest first."
  (mapcar #'row->revision
          (fetch "SELECT * FROM content_revisions WHERE content_id = ? ORDER BY id" content-id)))

(defun import-revision (content-id event data &key (by "") created-at)
  "Append a revision as it was written elsewhere. Imported oldest first, so the
ids keep the order they had."
  (exec "INSERT INTO content_revisions (content_id, event, data, written_by, created_at) VALUES (?, ?, ?, ?, ?)"
        content-id event (to-json data) (or by "") (or created-at (now-iso))))
