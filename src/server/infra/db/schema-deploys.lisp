(defpackage #:koya-server/infra/db/schema-deploys
  (:use #:cl)
  (:import-from #:koya-server/infra/db/connection #:exec #:fetch #:fetch-one #:col)
  (:import-from #:koya-core/ulid
                #:make-ulid)
  (:import-from #:koya-core/time
                #:now-iso)
  (:import-from #:koya-core/json
                #:parse-json #:to-json)
  (:import-from #:koya-server/domain/deploy
                #:make-deploy #:make-change)
  (:import-from #:koya-core/diff
                #:change->jobject #:destructive-change-p)
  (:import-from #:koya-server/usecases/ports/deploys
                #:+deploys-kept+ #:list-deploys #:count-deploys)
  (:export #:record-deploy))
(in-package #:koya-server/infra/db/schema-deploys)

(defun jobject->change (object)
  (make-change :op (gethash "op" object)
               :destructive (and (gethash "destructive" object) t)
               :description (gethash "description" object)))

(defun row->deploy (row)
  (make-deploy :id (col row "id")
               :space (col row "space")
               :changes (map 'list #'jobject->change (parse-json (col row "changes")))
               :change-count (col row "change_count")
               :destructive (plusp (or (col row "destructive") 0))
               :by (col row "deployed_by")
               :created-at (col row "created_at")))

(defun record-deploy (space changes &key (by ""))
  (when changes
    (let ((id (make-ulid)))
      (exec "INSERT INTO schema_deploys (id, space, changes, change_count, destructive, deployed_by, created_at)
             VALUES (?, ?, ?, ?, ?, ?, ?)"
            id space
            (to-json (map 'vector #'change->jobject changes))
            (length changes)
            (if (some #'destructive-change-p changes) 1 0)
            (or by "")
            (now-iso))
      (exec "DELETE FROM schema_deploys
              WHERE space = ?
                AND id NOT IN (SELECT id FROM schema_deploys WHERE space = ? ORDER BY id DESC LIMIT ?)"
            space space +deploys-kept+)
      id)))

(defmethod list-deploys (space &key (limit 25) (offset 0))
  (mapcar #'row->deploy
          (fetch "SELECT * FROM schema_deploys WHERE space = ? ORDER BY id DESC LIMIT ? OFFSET ?"
                 space limit offset)))

(defmethod count-deploys (space)
  (or (col (fetch-one "SELECT COUNT(*) AS n FROM schema_deploys WHERE space = ?" space) "n") 0))
