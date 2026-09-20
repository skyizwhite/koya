(defpackage #:koya-server/db/media
  (:use #:cl)
  (:import-from #:koya-server/db/connection
                #:exec #:fetch #:fetch-one #:col)
  (:import-from #:koya/core/ulid
                #:make-ulid)
  (:import-from #:koya/core/time
                #:now-iso)
  (:export #:insert-media
           #:find-media
           #:list-media
           #:count-media
           #:update-media
           #:delete-media
           #:media-references
           #:media-reference-counts
           #:media-id #:media-space #:media-filename #:media-mime #:media-size
           #:media-width #:media-height #:media-alt #:media-created-at))
(in-package #:koya-server/db/media)

;;; Rows of the media table. The file itself lives on disk (see lib/media-store);
;;; this module only knows the metadata.

(defstruct media
  id space filename mime size width height alt created-at)

(defun row->media (row)
  (make-media :id (col row "id") :space (col row "space") :filename (col row "filename")
              :mime (col row "mime") :size (col row "size")
              :width (col row "width") :height (col row "height")
              :alt (col row "alt") :created-at (col row "created_at")))

(defun insert-media (space &key filename mime size width height (alt "") (id (make-ulid)))
  (exec "INSERT INTO media (id, space, filename, mime, size, width, height, alt, created_at)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)"
        id space filename mime size width height alt (now-iso))
  (find-media space id))

(defun find-media (space id)
  (let ((row (fetch-one "SELECT * FROM media WHERE space = ? AND id = ?" space id)))
    (and row (row->media row))))

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

(defun count-media (space &key search)
  (multiple-value-bind (where params) (search-clause search)
    (col (apply #'fetch-one (format nil "SELECT COUNT(*) AS n FROM media WHERE space = ?~a" where) space params) "n")))

(defun update-media (space id &key alt)
  (when alt
    (exec "UPDATE media SET alt = ? WHERE space = ? AND id = ?" alt space id))
  (find-media space id))

(defun delete-media (space id)
  (exec "DELETE FROM media WHERE space = ? AND id = ?" space id))

(defun media-references (space id)
  "Number of contents in SPACE whose published or draft data mentions ID, as a
:media field value or inside richtext HTML (the URL contains the id)."
  (let ((needle (format nil "%~a%" id)))
    (col (fetch-one "SELECT COUNT(*) AS n FROM contents WHERE space = ? AND (published LIKE ? OR draft LIKE ?)"
                    space needle needle)
         "n")))

(defun media-reference-counts (space ids)
  "Hash of id -> number of contents in SPACE mentioning it, for all IDS in one pass
over the space's content data (a page of the library asks for 48 at once)."
  (let ((counts (make-hash-table :test 'equal)))
    (dolist (id ids) (setf (gethash id counts) 0))
    (when ids
      (dolist (row (fetch "SELECT published, draft FROM contents WHERE space = ?" space))
        (let ((text (concatenate 'string (or (col row "published") "") (or (col row "draft") ""))))
          (dolist (id ids)
            (when (search id text) (incf (gethash id counts)))))))
    counts))
