(defpackage #:koya-server/infra/db/webhook-deliveries
  (:use #:cl)
  (:import-from #:koya-core/data #:blank-p)
  (:import-from #:koya-server/infra/db/connection #:exec #:fetch #:fetch-one #:fetch-value #:col)
  (:import-from #:koya-server/infra/db/sql #:sql #:bound #:fragment #:all-of)
  (:import-from #:koya-server/domain/webhook-delivery
                #:make-delivery)
  (:import-from #:koya-core/ulid
                #:make-ulid)
  (:import-from #:koya-core/time
                #:now-iso)
  (:import-from #:koya-server/usecases/ports/webhooks
                #:+deliveries-kept+ #:record-delivery #:list-deliveries #:count-deliveries #:find-delivery
                #:delivery-labels #:delivery-models)
  (:export #:+max-response-chars+))
(in-package #:koya-server/infra/db/webhook-deliveries)

(defparameter +max-response-chars+ 4000)

(defun row->delivery (row)
  (make-delivery :id (col row "id") :space (col row "space") :label (col row "label")
                 :url (col row "url") :model (col row "model") :event (col row "event")
                 :content-id (col row "content_id")
                 :ok (plusp (or (col row "ok") 0))
                 :status (col row "status") :response (col row "response")
                 :error (col row "error") :duration-ms (col row "duration_ms")
                 :created-at (col row "created_at")))

(defun clip (text)
  (cond ((null text) "")
        ((stringp text)
         (if (> (length text) +max-response-chars+)
             (concatenate 'string (subseq text 0 +max-response-chars+)
                          (format nil "~%… (~a characters in all)" (length text)))
             text))
        ((typep text 'sequence) (format nil "<~a bytes, not text>" (length text)))
        (t (princ-to-string text))))

(defmethod record-delivery (space &key label url model event content-id ok status response error duration-ms)
  (let ((id (make-ulid)))
    (exec "INSERT INTO webhook_deliveries
             (id, space, label, url, model, event, content_id, ok, status, response, error, duration_ms, created_at)
           VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)"
          id space (or label "") (or url "") (or model "") (or event "") (or content-id "")
          (if ok 1 0) status (clip response) (clip error) duration-ms (now-iso))
    (exec "DELETE FROM webhook_deliveries
            WHERE space = ?
              AND id NOT IN (SELECT id FROM webhook_deliveries WHERE space = ? ORDER BY id DESC LIMIT ?)"
          space space +deliveries-kept+)
    id))

(defun deliveries-where (space label model)
  (all-of (list (sql "space = ?" space)
                (unless (blank-p label) (sql "label = ?" label))
                (unless (blank-p model) (sql "model = ?" model)))))

(defmethod list-deliveries (space &key label model (limit 50) (offset 0))
  (mapcar #'row->delivery
          (fetch (fragment "SELECT * FROM webhook_deliveries WHERE ~a ORDER BY id DESC LIMIT ~a OFFSET ~a"
                           (deliveries-where space label model) (bound limit) (bound offset)))))

(defmethod count-deliveries (space &key label model)
  (fetch-value (fragment "SELECT COUNT(*) FROM webhook_deliveries WHERE ~a" (deliveries-where space label model))))

(defun non-blank (values)
  (remove "" values :test #'string=))

(defmethod delivery-labels (space)
  (non-blank (mapcar #'second (fetch "SELECT DISTINCT label FROM webhook_deliveries WHERE space = ? ORDER BY label" space))))

(defmethod delivery-models (space)
  (non-blank (mapcar #'second (fetch "SELECT DISTINCT model FROM webhook_deliveries WHERE space = ? ORDER BY model" space))))

(defmethod find-delivery (space id)
  (let ((row (fetch-one "SELECT * FROM webhook_deliveries WHERE space = ? AND id = ?" space id)))
    (and row (row->delivery row))))
