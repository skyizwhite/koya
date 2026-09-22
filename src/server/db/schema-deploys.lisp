(defpackage #:koya-server/db/schema-deploys
  (:use #:cl)
  (:import-from #:koya-server/db/connection
                #:exec #:fetch #:fetch-one #:col)
  (:import-from #:koya/core/ulid
                #:make-ulid)
  (:import-from #:koya/core/time
                #:now-iso)
  (:import-from #:koya/core/json
                #:parse-json #:to-json #:jget)
  (:import-from #:koya/core/diff
                #:change->jobject #:destructive-change-p)
  (:export #:record-deploy
           #:list-deploys
           #:count-deploys
           #:+keep-per-space+
           #:deploy-id #:deploy-space #:deploy-changes #:deploy-change-count
           #:deploy-destructive #:deploy-by #:deploy-created-at
           #:change-op #:change-path #:change-destructive #:change-description))
(in-package #:koya-server/db/schema-deploys)

;;; One row per deploy that changed something, holding the changes in the wire
;;; format (core/diff's CHANGE->JOBJECT). The schema document itself is not kept:
;;; this says what changed, not what it was.

(defparameter +keep-per-space+ 100
  "Deploys kept per space; older rows are dropped as new ones arrive.")

(defstruct deploy
  id space changes change-count destructive by created-at)

(defun row->deploy (row)
  (make-deploy :id (col row "id")
               :space (col row "space")
               :changes (coerce (parse-json (col row "changes")) 'list)
               :change-count (col row "change_count")
               :destructive (plusp (or (col row "destructive") 0))
               :by (col row "deployed_by")
               :created-at (col row "created_at")))

(defun change-op (change) (jget change "op"))
(defun change-path (change) (jget change "path"))
(defun change-destructive (change) (and (jget change "destructive") t))
(defun change-description (change) (jget change "description"))

(defun record-deploy (space changes &key (by ""))
  "Store what a deploy changed. CHANGES is the diff's change plists; NIL records
nothing. Returns the new row's id, or NIL."
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
      ;; ULIDs sort by time, so the newest rows are the largest ids
      (exec "DELETE FROM schema_deploys
              WHERE space = ?
                AND id NOT IN (SELECT id FROM schema_deploys WHERE space = ? ORDER BY id DESC LIMIT ?)"
            space space +keep-per-space+)
      id)))

(defun list-deploys (space &key (limit 25) (offset 0))
  "Newest first, to the millisecond a ULID carries."
  (mapcar #'row->deploy
          (fetch "SELECT * FROM schema_deploys WHERE space = ? ORDER BY id DESC LIMIT ? OFFSET ?"
                 space limit offset)))

(defun count-deploys (space)
  (or (col (fetch-one "SELECT COUNT(*) AS n FROM schema_deploys WHERE space = ?" space) "n") 0))
