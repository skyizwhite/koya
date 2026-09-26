(defpackage #:koya-server/infra/db/media
  (:use #:cl)
  (:import-from #:koya-server/infra/db/connection #:exec #:fetch #:fetch-one #:col)
  (:import-from #:koya-server/domain/media
                #:make-media #:media-id)
  (:import-from #:koya-core/ulid
                #:make-ulid)
  (:import-from #:koya-core/time
                #:now-iso)
  (:import-from #:koya-server/usecases/ports/media
                #:insert-media #:find-media #:find-media-by-ids #:list-media #:space-media
                #:count-media #:update-media #:delete-media))
(in-package #:koya-server/infra/db/media)

;;; Rows of the media table. The file itself lives on disk (see infra/media-files);
;;; this module only knows the metadata.

(defun row->media (row)
  (make-media :id (col row "id") :space (col row "space") :filename (col row "filename")
              :mime (col row "mime") :size (col row "size")
              :width (col row "width") :height (col row "height")
              :alt (col row "alt") :created-at (col row "created_at")))

(defmethod insert-media (space &key filename mime size width height (alt "") (id (make-ulid)) created-at)
  (exec "INSERT INTO media (id, space, filename, mime, size, width, height, alt, created_at)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)"
        id space filename mime size width height alt (or created-at (now-iso)))
  (find-media space id))

(defmethod find-media (space id)
  (let ((row (fetch-one "SELECT * FROM media WHERE space = ? AND id = ?" space id)))
    (and row (row->media row))))

(defmethod find-media-by-ids (space ids)
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

(defmethod list-media (space &key search (limit 60) (offset 0))
  (multiple-value-bind (where params) (search-clause search)
    (mapcar #'row->media
            (apply #'fetch (format nil "SELECT * FROM media WHERE space = ?~a ORDER BY created_at DESC, id DESC LIMIT ? OFFSET ?" where)
                   space (append params (list limit offset))))))

(defmethod space-media (space)
  (mapcar #'row->media (fetch "SELECT * FROM media WHERE space = ? ORDER BY created_at, id" space)))

(defmethod count-media (space &key search)
  (multiple-value-bind (where params) (search-clause search)
    (col (apply #'fetch-one (format nil "SELECT COUNT(*) AS n FROM media WHERE space = ?~a" where) space params) "n")))

(defmethod update-media (space id &key alt)
  (when alt
    (exec "UPDATE media SET alt = ? WHERE space = ? AND id = ?" alt space id))
  (find-media space id))

(defmethod delete-media (space id)
  (exec "DELETE FROM media WHERE space = ? AND id = ?" space id))
