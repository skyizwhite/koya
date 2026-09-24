(defpackage #:koya-server/db/media
  (:use #:cl)
  (:import-from #:koya-server/db/connection
                #:exec #:fetch #:fetch-one #:col)
  (:import-from #:koya/core/ulid
                #:make-ulid)
  (:import-from #:koya/core/time
                #:now-iso)
  (:import-from #:koya/core/json
                #:parse-json)
  (:import-from #:koya/core/schema
                #:schema-models #:model-name #:model-fields #:field-name #:field-type)
  (:import-from #:koya-server/db/schema-store
                #:load-schema)
  (:export #:insert-media
           #:find-media
           #:find-media-by-ids
           #:list-media
           #:space-media
           #:count-media
           #:update-media
           #:delete-media
           #:media-references
           #:media-reference-counts
           #:media-id #:media-space #:media-filename #:media-mime #:media-size
           #:media-width #:media-height #:media-alt #:media-created-at))
(in-package #:koya-server/db/media)

;;; Rows of the media table. The file itself lives on disk (see features/media/store);
;;; this module only knows the metadata.

(defstruct media
  id space filename mime size width height alt created-at)

(defun row->media (row)
  (make-media :id (col row "id") :space (col row "space") :filename (col row "filename")
              :mime (col row "mime") :size (col row "size")
              :width (col row "width") :height (col row "height")
              :alt (col row "alt") :created-at (col row "created_at")))

(defun insert-media (space &key filename mime size width height (alt "") (id (make-ulid)) created-at)
  (exec "INSERT INTO media (id, space, filename, mime, size, width, height, alt, created_at)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)"
        id space filename mime size width height alt (or created-at (now-iso)))
  (find-media space id))

(defun find-media (space id)
  (let ((row (fetch-one "SELECT * FROM media WHERE space = ? AND id = ?" space id)))
    (and row (row->media row))))

(defun find-media-by-ids (space ids)
  "Hash of id -> media for those of IDS that are in SPACE's library."
  (let ((table (make-hash-table :test 'equal))
        (ids (remove-duplicates ids :test #'equal)))
    (when ids
      (dolist (row (apply #'fetch (format nil "SELECT * FROM media WHERE space = ? AND id IN (~{~*?~^, ~})" ids)
                          space ids))
        (let ((media (row->media row)))
          (setf (gethash (media-id media) table) media))))
    table))

(defun search-clause (search)
  (if (and search (plusp (length search)))
      (values " AND filename LIKE ? ESCAPE '\\'"
              (list (format nil "%~a%" (with-output-to-string (out)
                                          (loop :for c :across search
                                                :do (when (member c '(#\% #\_ #\\)) (write-char #\\ out))
                                                    (write-char c out))))))
      (values "" '())))

(defun list-media (space &key search (limit 60) (offset 0))
  "Newest first. SEARCH matches the file name."
  (multiple-value-bind (where params) (search-clause search)
    (mapcar #'row->media
            (apply #'fetch (format nil "SELECT * FROM media WHERE space = ?~a ORDER BY created_at DESC, id DESC LIMIT ? OFFSET ?" where)
                   space (append params (list limit offset))))))

(defun space-media (space)
  "Every media of SPACE, oldest first."
  (mapcar #'row->media (fetch "SELECT * FROM media WHERE space = ? ORDER BY created_at, id" space)))

(defun count-media (space &key search)
  (multiple-value-bind (where params) (search-clause search)
    (col (apply #'fetch-one (format nil "SELECT COUNT(*) AS n FROM media WHERE space = ?~a" where) space params) "n")))

(defun update-media (space id &key alt)
  (when alt
    (exec "UPDATE media SET alt = ? WHERE space = ? AND id = ?" alt space id))
  (find-media space id))

(defun delete-media (space id)
  (exec "DELETE FROM media WHERE space = ? AND id = ?" space id))

(defun media-fields (space)
  "Hash of model name -> the fields of that model in SPACE's schema that can hold
a media: :media fields by id, :richtext by URL (which contains the id)."
  (let ((table (make-hash-table :test 'equal))
        (schema (load-schema space)))
    (dolist (model (and schema (schema-models schema)) table)
      (setf (gethash (model-name model) table)
            (remove-if-not (lambda (f) (member (field-type f) '(:media :richtext))) (model-fields model))))))

;; Only the fields in the schema count: a deploy that removes a field leaves its
;; values in the stored JSON, where nothing reads them any more, and they must
;; not keep a file from being deleted.
(defun mentioned-ids (fields json ids)
  "Those of IDS that the FIELDS of the content data JSON (a string, or NIL) mention."
  (let ((data (and json (parse-json json))))
    (when (hash-table-p data)
      (remove-if-not
       (lambda (id)
         (some (lambda (field)
                 (let ((value (gethash (field-name field) data)))
                   (and (stringp value)
                        (if (eq (field-type field) :media) (string= value id) (search id value)))))
               fields))
       ids))))

(defun media-reference-counts (space ids &key (where "") params)
  "Hash of id -> number of contents in SPACE whose published or draft data mentions
it in a :media or :richtext field of the current schema, for all IDS in one pass
over the space's contents (a page of the library asks for all its cards at once).
WHERE and PARAMS narrow the rows read."
  (let ((counts (make-hash-table :test 'equal))
        (fields (media-fields space)))
    (dolist (id ids) (setf (gethash id counts) 0))
    (when ids
      (dolist (row (apply #'fetch (format nil "SELECT model, published, draft FROM contents WHERE space = ?~a" where)
                          space params))
        (let ((model-fields (gethash (col row "model") fields)))
          (dolist (id (union (mentioned-ids model-fields (col row "published") ids)
                             (mentioned-ids model-fields (col row "draft") ids)
                             :test #'string=))
            (incf (gethash id counts))))))
    counts))

(defun media-references (space id)
  "Number of contents in SPACE that mention ID (see MEDIA-REFERENCE-COUNTS)."
  (let ((needle (format nil "%~a%" id)))
    ;; LIKE only skips the contents that cannot mention it; the fields decide
    (gethash id (media-reference-counts space (list id) :where " AND (published LIKE ? OR draft LIKE ?)"
                                                        :params (list needle needle)))))
