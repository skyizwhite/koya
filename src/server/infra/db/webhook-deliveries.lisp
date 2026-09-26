(defpackage #:koya-server/infra/db/webhook-deliveries
  (:use #:cl)
  (:import-from #:koya-server/infra/db/connection #:exec #:fetch #:fetch-one #:col)
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

;;; What came back from each webhook call, so the admin UI can show whether the
;;; receiver accepted it. Only the newest +DELIVERIES-KEPT+ rows of a space are
;;; kept: this is a log to glance at after a publish, not an audit trail.

(defparameter +max-response-chars+ 4000
  "How much of a response body is stored. A receiver that answers with a page
instead of a line should not fill the database.")

(defun row->delivery (row)
  (make-delivery :id (col row "id") :space (col row "space") :label (col row "label")
                 :url (col row "url") :model (col row "model") :event (col row "event")
                 :content-id (col row "content_id")
                 :ok (plusp (or (col row "ok") 0))
                 :status (col row "status") :response (col row "response")
                 :error (col row "error") :duration-ms (col row "duration_ms")
                 :created-at (col row "created_at")))

(defun clip (text)
  "TEXT as a string the log can hold: bodies that are not text are named, not stored."
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
    ;; ULIDs sort by time, so the newest rows are the largest ids
    (exec "DELETE FROM webhook_deliveries
            WHERE space = ?
              AND id NOT IN (SELECT id FROM webhook_deliveries WHERE space = ? ORDER BY id DESC LIMIT ?)"
          space space +deliveries-kept+)
    id))

(defun blank-p (value) (or (null value) (zerop (length value))))

(defun filter-clause (label model)
  "The WHERE fragment and parameters for whichever of LABEL and MODEL is given."
  (let ((where "") (params '()))
    (unless (blank-p label)
      (setf where (concatenate 'string where " AND label = ?")
            params (append params (list label))))
    (unless (blank-p model)
      (setf where (concatenate 'string where " AND model = ?")
            params (append params (list model))))
    (values where params)))

(defmethod list-deliveries (space &key label model (limit 50) (offset 0))
  (multiple-value-bind (where params) (filter-clause label model)
    (mapcar #'row->delivery
            (apply #'fetch
                   (format nil "SELECT * FROM webhook_deliveries WHERE space = ?~a ORDER BY id DESC LIMIT ? OFFSET ?" where)
                   space (append params (list limit offset))))))

(defmethod count-deliveries (space &key label model)
  (multiple-value-bind (where params) (filter-clause label model)
    (or (col (apply #'fetch-one
                    (format nil "SELECT COUNT(*) AS n FROM webhook_deliveries WHERE space = ?~a" where)
                    space params)
             "n")
        0)))

(defun distinct-column (space column)
  (remove "" (mapcar (lambda (row) (col row column))
                     (fetch (format nil "SELECT DISTINCT ~a AS ~:*~a FROM webhook_deliveries WHERE space = ? ORDER BY ~:*~a" column)
                            space))
          :test #'string=))

(defmethod delivery-labels (space)
  (distinct-column space "label"))

(defmethod delivery-models (space)
  (distinct-column space "model"))

(defmethod find-delivery (space id)
  (let ((row (fetch-one "SELECT * FROM webhook_deliveries WHERE space = ? AND id = ?" space id)))
    (and row (row->delivery row))))
