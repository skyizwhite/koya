(defpackage #:koya-server/usecases/spaces/archive
  (:use #:cl)
  (:import-from #:koya-server/domain/errors
                #:invalid-input #:conflict #:not-found)
  (:import-from #:koya-server/usecases/ports/store
                #:with-transaction)
  (:import-from #:koya-server/usecases/actor
                #:*actor*)
  (:import-from #:koya-server/usecases/ports/spaces
                #:load-schema #:find-space #:insert-space #:space-webhook-secret
                #:set-webhook-secret)
  (:import-from #:koya-server/usecases/schema/deploy
                #:replace-schema)
  (:import-from #:koya-server/usecases/ports/keys
                #:stored-delivery-keys #:import-delivery-key #:stored-management-keys
                #:import-management-key)
  (:import-from #:koya-server/usecases/ports/contents
                #:space-contents #:insert-content #:content-history #:record-revision)
  (:import-from #:koya-server/domain/content
                #:make-content #:status-of #:content-id #:content-model #:content-published #:content-draft
                #:content-draft-key #:content-created-at #:content-updated-at
                #:content-published-at #:content-revised-at)
  (:import-from #:koya-server/domain/revision
                #:revision-event #:revision-data #:revision-by #:revision-created-at)
  (:import-from #:koya-server/usecases/ports/media
                #:space-media #:insert-media #:count-media #:media-file-exists-p #:write-media-file
                #:delete-media-file)
  (:import-from #:koya-server/usecases/ports/archives
                #:write-archive #:create-upload #:upload-size #:append-to-upload #:delete-upload
                #:call-with-upload #:archive-entry-size #:archive-entry-bytes #:purge-stale-archives)
  (:import-from #:koya-server/domain/media
                #:media-id #:media-space #:media-filename #:media-mime #:media-size #:media-width
                #:media-height #:media-alt #:media-created-at #:+max-upload-bytes+)
  (:import-from #:koya-server/domain/image #:sniff-image #:image-extension)
  (:import-from #:koya/core/schema
                #:schema-models #:schema-model #:schema->jobject #:jobject->schema #:slug-name-p)
  (:import-from #:koya/core/json
                #:jobject #:jget #:json-null #:json-null-p #:json-array-p #:parse-json #:to-json)
  (:import-from #:koya/core/time
                #:now-iso)
  (:import-from #:cl-ppcre
                #:scan)
  (:import-from #:babel
                #:string-to-octets #:octets-to-string)
  (:import-from #:bordeaux-threads-2)
  (:export #:export-space
           #:begin-import
           #:continue-import
           #:finish-import
           #:archive-file-name
           #:archive-error))
(in-package #:koya-server/usecases/spaces/archive)

;;; A space as one zip: space.json -- the schema, every content with its draft,
;;; its system timestamps and its history, the media rows, the keys and the
;;; webhook secret -- plus the media files under media/. Importing makes the space
;;; again under the same name, with the same ids, so references, media fields,
;;; the /media/ paths in richtext and the site's keys and secret all still work.
;;;
;;; Keys are stored as SHA-256 and move as that, so the archive holds no key
;;; that can be used; it does hold the webhook secret and every draft, so it is
;;; to be kept as privately as the database itself.
;;;
;;; A space has no size limit, so neither has its archive: the files are copied
;;; into it and out of it one at a time (ports/archives), and an import arrives
;;; in pieces. What is held in memory is space.json and one file.

(defparameter +archive-version+ 1)

(defparameter +media-id-pattern+ "^[0-9A-Z]{26}\\z"
  "What STORE-UPLOAD makes, and what /media/ serves. An archive's ids become file
names, so nothing else is accepted.")

(define-condition archive-error (invalid-input) ())

(defun fail (fmt &rest args)
  (error 'archive-error :message (apply #'format nil fmt args)))

(defun or-null (value) (if (null value) json-null value))
(defun nullable (value) (if (json-null-p value) nil value))

(defun archive-file-name (space)
  (format nil "~a-~a.zip" space (remove-if-not #'digit-char-p (subseq (now-iso) 0 19))))

;;; --- Export -------------------------------------------------------------------

(defun revision->jobject (revision)
  (jobject "event" (revision-event revision)
           "data" (revision-data revision)
           "writtenBy" (revision-by revision)
           "createdAt" (revision-created-at revision)))

(defun content->jobject (content)
  (jobject "id" (content-id content)
           "model" (content-model content)
           "published" (or-null (content-published content))
           "draft" (or-null (content-draft content))
           "draftKey" (or-null (content-draft-key content))
           "createdAt" (content-created-at content)
           "updatedAt" (content-updated-at content)
           "publishedAt" (or-null (content-published-at content))
           "revisedAt" (or-null (content-revised-at content))
           "revisions" (map 'vector #'revision->jobject (content-history (content-id content)))))

(defun media-entry-name (id mime)
  (format nil "media/~a.~a" id (image-extension mime)))

(defun media->jobject (media)
  (jobject "id" (media-id media)
           "filename" (media-filename media)
           "mime" (media-mime media)
           "size" (media-size media)
           "width" (or-null (media-width media))
           "height" (or-null (media-height media))
           "alt" (media-alt media)
           "createdAt" (media-created-at media)
           "file" (media-entry-name (media-id media) (media-mime media))))

(defun key->jobject (key)
  (jobject "id" (getf key :id) "keyHash" (getf key :hash)
           "label" (getf key :label) "createdAt" (getf key :created-at)))

(defun export-space (space)
  "The archive of SPACE, written to a file whose pathname is returned; the caller
deletes it once it is sent. Signals ARCHIVE-ERROR when the file of a media is
missing: an archive without it would not restore."
  (let* ((schema (or (load-schema space) (fail "Space ~a not found" space)))
         (media (space-media space))
         (document (jobject "koyaExport" +archive-version+
                            "space" space
                            "exportedAt" (now-iso)
                            "schema" (schema->jobject schema)
                            "contents" (map 'vector #'content->jobject (space-contents space))
                            "media" (map 'vector #'media->jobject media)
                            "webhookSecret" (space-webhook-secret space)
                            "deliveryKeys" (map 'vector #'key->jobject (stored-delivery-keys space))
                            "managementKeys" (map 'vector #'key->jobject (stored-management-keys space)))))
    (dolist (m media)
      (unless (media-file-exists-p (media-space m) (media-id m) (media-mime m))
        (fail "The file of ~a (~a) is missing from the media library" (media-filename m) (media-id m))))
    (purge-stale-archives)
    (write-archive (cons (cons "space.json" (string-to-octets (to-json document) :encoding :utf-8))
                         (mapcar (lambda (m) (cons (media-entry-name (media-id m) (media-mime m)) m))
                                 media)))))

;;; --- Import -------------------------------------------------------------------
;;;
;;; An archive arrives in pieces (BEGIN-IMPORT, CONTINUE-IMPORT) and is read once
;;; whole (FINISH-IMPORT), one file at a time.

(defun read-document (archive)
  (let* ((json (or (archive-entry-bytes archive "space.json") (fail "The archive has no space.json")))
         (document (handler-case (parse-json (octets-to-string json :encoding :utf-8))
                     (error () (fail "space.json is not valid JSON")))))
    (unless (hash-table-p document) (fail "space.json must be an object"))
    (unless (eql (jget document "koyaExport") +archive-version+)
      (fail "Unsupported archive version ~s (expected ~a)" (jget document "koyaExport") +archive-version+))
    document))

(defun string-field (object key &key required)
  (let ((value (nullable (jget object key))))
    (cond ((stringp value) value)
          ((and (null value) (not required)) nil)
          (t (fail "~a must be a string" key)))))

(defun data-field (object key)
  (let ((value (nullable (jget object key))))
    (unless (or (null value) (hash-table-p value)) (fail "~a must be an object or null" key))
    value))

(defun parse-content (object space schema)
  "(content revisions) for one content of space.json."
  (unless (hash-table-p object) (fail "Each content must be an object"))
  (let* ((id (string-field object "id" :required t))
         (model (string-field object "model" :required t))
         (published (data-field object "published"))
         (draft (data-field object "draft"))
         (revisions (or (nullable (jget object "revisions")) #())))
    (unless (schema-model schema model) (fail "Content ~a belongs to ~a, which the schema has no model for" id model))
    (unless (or published draft) (fail "Content ~a has neither published data nor a draft" id))
    (unless (json-array-p revisions) (fail "The revisions of content ~a must be an array" id))
    (list
     (make-content :id id :space space :model model :status (status-of published draft)
                   :published published :draft draft
                   :draft-key (and draft (string-field object "draftKey"))
                   :created-at (string-field object "createdAt" :required t)
                   :updated-at (string-field object "updatedAt" :required t)
                   :published-at (and published (string-field object "publishedAt"))
                   :revised-at (and published (string-field object "revisedAt")))
     (map 'list (lambda (r)
                  (unless (and (hash-table-p r) (hash-table-p (jget r "data")))
                    (fail "A revision of content ~a has no data" id))
                  (list :event (string-field r "event" :required t)
                        :data (jget r "data")
                        :by (or (string-field r "writtenBy") "")
                        :created-at (string-field r "createdAt" :required t)))
          revisions))))

(defun parse-media (object archive)
  "The media row as a plist with the :entry naming its file in ARCHIVE, which is
checked the way an upload is. The bytes are not kept: they are read again when
the file is written."
  (unless (hash-table-p object) (fail "Each media must be an object"))
  (let* ((id (string-field object "id" :required t))
         (mime (string-field object "mime" :required t)))
    (unless (scan +media-id-pattern+ id) (fail "~s is not a media id" id))
    (unless (image-extension mime) (fail "Media ~a is ~a, which is not an accepted image type" id mime))
    (let* ((entry (media-entry-name id mime))
           (size (or (archive-entry-size archive entry) (fail "The archive has no file for media ~a" id))))
      ;; before reading it: an upload is never larger, and a file that says it is
      ;; would be held whole
      (when (> size +max-upload-bytes+)
        (fail "The file of media ~a is larger than an upload may be" id))
      (let ((bytes (archive-entry-bytes archive entry)))
        (multiple-value-bind (sniffed width height) (sniff-image bytes)
          (unless (equal sniffed mime) (fail "The file of media ~a is not the ~a it says it is" id mime))
          (list :id id :mime mime :entry entry :size (length bytes) :width width :height height
                :filename (or (string-field object "filename") "upload")
                :alt (or (string-field object "alt") "")
                :created-at (string-field object "createdAt" :required t)))))))

(defun parse-keys (document key)
  "The keys under KEY of space.json as plists for IMPORT-*-KEY."
  (let ((keys (or (nullable (jget document key)) #())))
    (unless (json-array-p keys) (fail "~a must be an array" key))
    (map 'list (lambda (k)
                 (unless (hash-table-p k) (fail "Each of ~a must be an object" key))
                 (let ((hash (string-field k "keyHash" :required t)))
                   (unless (scan "^[0-9a-f]{64}\\z" hash) (fail "~s is not a key hash" hash))
                   (list :id (string-field k "id" :required t) :hash hash
                         :label (or (string-field k "label") "")
                         :created-at (string-field k "createdAt" :required t))))
         keys)))

(defun check-target (space)
  "A space is imported only where it meets nothing of its own: a name that is
free, or a space that is empty -- no models (so no contents), no media and no
keys. Its webhooks and webhook secret are the archive's to replace."
  (when (and (find-space space)
             (or (schema-models (load-schema space))
                 (plusp (count-media space))
                 (stored-delivery-keys space)
                 (stored-management-keys space)))
    (fail "Space ~a is not empty. Import into a new space, or one with no models, media or keys." space)))

(defun write-media-files (space archive media written)
  "Write every file, pushing each media onto the list in the cons WRITTEN once its
file is made, so a caller that fails later takes away only what this import
made. A file already there is an error, never replaced: it may be another
import's."
  (dolist (m media)
    (unless (write-media-file space (getf m :id) (getf m :mime) (archive-entry-bytes archive (getf m :entry))
                              :new t)
      (fail "The file of media ~a is already in the media library" (getf m :id)))
    (push m (car written))))

(defvar *uploads-lock* (bordeaux-threads-2:make-lock :name "koya-uploads")
  "Held while a piece is checked and added, and while an upload is imported, so
no two requests work on one upload at once.")

(defun no-such-import (id)
  (error 'not-found :message (format nil "There is no import ~a; start again" id)))

(defun begin-import ()
  "Start an import. Returns the id its pieces are sent under."
  (purge-stale-archives)
  (create-upload))

(defun continue-import (id offset octets)
  "Add OCTETS to import ID. OFFSET is where they go: pieces arrive in order, and one
sent twice, or one that skipped ahead, is refused with a CONFLICT that says where
the import stands."
  (bordeaux-threads-2:with-lock-held (*uploads-lock*)
    (let ((size (or (upload-size id) (no-such-import id))))
      (unless (eql offset size)
        (error 'conflict :message (format nil "The import has ~a bytes; a piece at ~a does not follow them"
                                          size offset)))
      (append-to-upload id octets)
      (+ size (length octets)))))

(defun finish-import (id &key (by *actor*))
  "Make the space in the archive import ID collected again: its schema, contents
with their history, and media. Returns the space's name. Nothing is sent to its
webhooks. Signals ARCHIVE-ERROR (or a schema error) and changes nothing when the
archive is malformed or the space is not empty. The upload is gone afterwards,
whatever came of it."
  (bordeaux-threads-2:with-lock-held (*uploads-lock*)
    (unless (upload-size id) (no-such-import id))
    (unwind-protect (call-with-upload id (lambda (archive) (import-from-archive archive :by by)))
      (delete-upload id))))

(defun import-from-archive (archive &key by)
  (let* ((document (read-document archive))
         (space (string-field document "space" :required t))
         (schema (jobject->schema (jget document "schema"))))
    (unless (slug-name-p space) (fail "~s is not a space name" space))
    (check-target space)
    (import-into space archive schema
                 (map 'list (lambda (o) (parse-content o space schema))
                      (or (nullable (jget document "contents")) #()))
                 (map 'list (lambda (o) (parse-media o archive))
                      (or (nullable (jget document "media")) #()))
                 :secret (string-field document "webhookSecret")
                 :delivery-keys (parse-keys document "deliveryKeys")
                 :management-keys (parse-keys document "managementKeys")
                 :by by)))

(defun import-into (space archive schema contents media &key secret delivery-keys management-keys by)
  ;; the files first, as an upload does: a failed write must not leave rows
  ;; whose URLs 404; a failed transaction takes the files away again
  (let ((written (list '()))
        (done nil))
    (unwind-protect
         (progn
           (write-media-files space archive media written)
           (with-transaction
             ;; checked again inside: another import may have made it since
             (check-target space)
             (unless (find-space space) (insert-space space))
             (replace-schema space schema :by by)
             (when secret (set-webhook-secret space secret))
             (dolist (k delivery-keys) (apply #'import-delivery-key space k))
             (dolist (k management-keys) (apply #'import-management-key space k))
             (dolist (m media)
               (insert-media space :id (getf m :id) :filename (getf m :filename) :mime (getf m :mime)
                                   :size (getf m :size) :width (getf m :width) :height (getf m :height)
                                   :alt (getf m :alt) :created-at (getf m :created-at)))
             (loop :for (content revisions) :in contents
                   :do (insert-content content)
                       (dolist (r revisions)
                         (record-revision (content-id content) (getf r :event) (getf r :data)
                                          :by (getf r :by) :created-at (getf r :created-at)))))
           (setf done t))
      (unless done
        (dolist (m (car written))
          (delete-media-file space (getf m :id) (getf m :mime)))))
    space))
