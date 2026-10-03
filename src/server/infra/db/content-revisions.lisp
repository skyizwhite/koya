(defpackage #:koya-server/infra/db/content-revisions
  (:use #:cl)
  (:import-from #:koya-server/infra/db/connection #:exec #:fetch #:fetch-one #:col)
  (:import-from #:koya-server/domain/revision
                #:make-revision)
  (:import-from #:koya-core/time
                #:now-iso)
  (:import-from #:koya-core/json
                #:parse-json #:to-json)
  (:import-from #:koya-server/usecases/ports/contents
                #:record-revision #:list-revisions #:count-revisions #:find-revision
                #:content-history))
(in-package #:koya-server/infra/db/content-revisions)

(defun row->revision (row)
  (make-revision :id (col row "id")
                 :content-id (col row "content_id")
                 :event (col row "event")
                 :data (parse-json (col row "data"))
                 :by (col row "written_by")
                 :created-at (col row "created_at")))

(defmethod record-revision (space content-id event data &key (by "") created-at)
  (exec "INSERT INTO content_revisions (space, content_id, event, data, written_by, created_at) VALUES (?, ?, ?, ?, ?, ?)"
        space content-id event (to-json data) (or by "") (or created-at (now-iso))))

(defun where (published-only)
  (format nil "space = ? AND content_id = ?~:[~; AND event = 'publish'~]" published-only))

(defmethod list-revisions (space content-id &key published-only (limit 20) (offset 0))
  (mapcar #'row->revision
          (fetch (format nil "SELECT * FROM content_revisions WHERE ~a ORDER BY id DESC LIMIT ? OFFSET ?"
                         (where published-only))
                 space content-id limit offset)))

(defmethod count-revisions (space content-id &key published-only)
  (col (fetch-one (format nil "SELECT COUNT(*) AS n FROM content_revisions WHERE ~a" (where published-only))
                  space content-id)
       "n"))

(defmethod find-revision (space content-id id)
  (let ((row (fetch-one "SELECT * FROM content_revisions WHERE space = ? AND content_id = ? AND id = ?"
                        space content-id id)))
    (and row (row->revision row))))

(defmethod content-history (space content-id)
  (mapcar #'row->revision
          (fetch "SELECT * FROM content_revisions WHERE space = ? AND content_id = ? ORDER BY id" space content-id)))
