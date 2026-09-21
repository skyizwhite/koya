(defpackage #:koya-server/db/webhook-deliveries
  (:use #:cl)
  (:import-from #:koya-server/db/connection
                #:exec #:fetch #:fetch-one #:col)
  (:import-from #:koya/core/ulid
                #:make-ulid)
  (:import-from #:koya/core/time
                #:now-iso)
  (:export #:record-delivery
           #:list-deliveries
           #:count-deliveries
           #:find-delivery
           #:+keep-per-space+
           #:+max-response-chars+
           #:delivery-id #:delivery-space #:delivery-label #:delivery-url #:delivery-model
           #:delivery-event #:delivery-content-id #:delivery-ok #:delivery-status
           #:delivery-response #:delivery-error #:delivery-duration-ms #:delivery-created-at))
(in-package #:koya-server/db/webhook-deliveries)

;;; What came back from each webhook call, so the admin UI can show whether the
;;; receiver accepted it. Only the newest +KEEP-PER-SPACE+ rows of a space are
;;; kept: this is a log to glance at after a publish, not an audit trail.

(defparameter +keep-per-space+ 200
  "Deliveries kept per space; older rows are dropped as new ones arrive.")

(defparameter +max-response-chars+ 4000
  "How much of a response body is stored. A receiver that answers with a page
instead of a line should not fill the database.")

(defstruct delivery
  id space label url model event content-id ok status response error duration-ms created-at)

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

(defun record-delivery (space &key label url model event content-id ok status response error duration-ms)
  "Store one call's outcome and drop whatever now falls outside the cap."
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
          space space +keep-per-space+)
    id))

(defun label-clause (label)
  (if (and label (plusp (length label)))
      (values " AND label = ?" (list label))
      (values "" '())))

(defun list-deliveries (space &key label (limit 50) (offset 0))
  "Newest first. LABEL, when given, keeps only that webhook's calls."
  (multiple-value-bind (where params) (label-clause label)
    (mapcar #'row->delivery
            (apply #'fetch
                   (format nil "SELECT * FROM webhook_deliveries WHERE space = ?~a ORDER BY id DESC LIMIT ? OFFSET ?" where)
                   space (append params (list limit offset))))))

(defun count-deliveries (space &key label)
  (multiple-value-bind (where params) (label-clause label)
    (or (col (apply #'fetch-one
                    (format nil "SELECT COUNT(*) AS n FROM webhook_deliveries WHERE space = ?~a" where)
                    space params)
             "n")
        0)))

(defun find-delivery (space id)
  (let ((row (fetch-one "SELECT * FROM webhook_deliveries WHERE space = ? AND id = ?" space id)))
    (and row (row->delivery row))))
