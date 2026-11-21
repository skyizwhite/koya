(defpackage #:koya-server/infra/db/media
  (:use #:cl)
  (:import-from #:koya-core/data #:blank-p)
  (:import-from #:koya-server/infra/db/connection #:exec #:fetch #:fetch-one #:fetch-value #:col)
  (:import-from #:koya-server/infra/db/sql #:sql #:bound #:fragment #:all-of #:in-list #:like-pattern)
  (:import-from #:koya-server/domain/media
                #:make-media #:media-id)
  (:import-from #:koya-core/time
                #:now-iso)
  (:import-from #:koya-server/usecases/ports/media
                #:insert-media #:find-media #:find-media-by-ids #:list-media #:space-media
                #:count-media #:update-media #:delete-media))
(in-package #:koya-server/infra/db/media)

(defun row->media (row)
  (make-media :id (col row "id") :space (col row "space") :filename (col row "filename")
              :mime (col row "mime") :size (col row "size")
              :width (col row "width") :height (col row "height")
              :alt (col row "alt") :created-at (col row "created_at")))

(defmethod insert-media (space id &key filename mime size width height (alt "") created-at)
  (let ((row (fetch-one "INSERT INTO media (id, space, filename, mime, size, width, height, alt, created_at)
                         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                         ON CONFLICT (id) DO NOTHING
                         RETURNING *"
                        id space filename mime size width height alt (or created-at (now-iso)))))
    (and row (row->media row))))

(defmethod find-media (space id)
  (let ((row (fetch-one "SELECT * FROM media WHERE space = ? AND id = ?" space id)))
    (and row (row->media row))))

(defmethod find-media-by-ids (space ids)
  (let ((table (make-hash-table :test 'equal))
        (ids (remove-duplicates ids :test #'equal)))
    (when ids
      (dolist (row (fetch (fragment "SELECT * FROM media WHERE space = ~a AND id IN ~a" (bound space) (in-list ids))))
        (let ((media (row->media row)))
          (setf (gethash (media-id media) table) media))))
    table))

(defun media-where (space search)
  (all-of (list (sql "space = ?" space)
                (unless (blank-p search) (sql "filename LIKE ? ESCAPE '\\'" (like-pattern search))))))

(defmethod list-media (space &key search (limit 60) (offset 0))
  (mapcar #'row->media
          (fetch (fragment "SELECT * FROM media WHERE ~a ORDER BY created_at DESC, id DESC LIMIT ~a OFFSET ~a"
                           (media-where space search) (bound limit) (bound offset)))))

(defmethod space-media (space)
  (mapcar #'row->media (fetch "SELECT * FROM media WHERE space = ? ORDER BY created_at, id" space)))

(defmethod count-media (space &key search)
  (fetch-value (fragment "SELECT COUNT(*) FROM media WHERE ~a" (media-where space search))))

(defmethod update-media (space id &key alt)
  (when alt
    (exec "UPDATE media SET alt = ? WHERE space = ? AND id = ?" alt space id))
  (find-media space id))

(defmethod delete-media (space id)
  (exec "DELETE FROM media WHERE space = ? AND id = ?" space id))
