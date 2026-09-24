(defpackage #:koya-server/usecases/spaces/archive
  (:use #:cl)
  (:import-from #:koya-server/domain/errors
                #:invalid-input)
  (:import-from #:koya-server/usecases/ports/store
                #:with-transaction)
  (:import-from #:koya-server/usecases/actor
                #:*actor*)
  (:import-from #:koya-server/usecases/ports/spaces
                #:load-schema #:save-schema #:find-space #:insert-space #:space-webhook-secret
                #:set-webhook-secret)
  (:import-from #:koya-server/usecases/ports/keys
                #:stored-delivery-keys #:import-delivery-key #:stored-management-keys
                #:import-management-key)
  (:import-from #:koya-server/usecases/ports/contents
                #:space-contents #:import-content #:content-history #:import-revision)
  (:import-from #:koya-server/domain/content
                #:make-content #:content-id #:content-model #:content-published #:content-draft
                #:content-draft-key #:content-created-at #:content-updated-at
                #:content-published-at #:content-revised-at)
  (:import-from #:koya-server/domain/revision
                #:revision-event #:revision-data #:revision-by #:revision-created-at)
  (:import-from #:koya-server/usecases/ports/media
                #:space-media #:insert-media #:count-media #:media-file-path)
  (:import-from #:koya-server/domain/media
                #:media-id #:media-space #:media-filename #:media-mime #:media-size #:media-width
                #:media-height #:media-alt #:media-created-at)
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
  (:import-from #:org.shirakumo.zippy
                #:zip-file #:zip-entry #:compress-zip #:open-zip-file #:entries #:file-name
                #:entry-to-vector #:entry-to-file)
  (:export #:export-space
           #:import-space
           #:import-space-stream
           #:archive-file-name
           #:archive-error
           #:+max-archive-bytes+))
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

(defparameter +archive-version+ 1)

(defparameter +max-archive-bytes+ (* 512 1024 1024)
  "Largest archive /import accepts. It carries every media file of a space.")

(defparameter +media-id-pattern+ "^[0-9A-Z]{26}\\z"
  "What STORE-UPLOAD makes, and what /media/ serves. An archive's ids become file
names, so nothing else is accepted.")

(define-condition archive-error (invalid-input) ())

(defun fail (fmt &rest args)
  (error 'archive-error :message (apply #'format nil fmt args)))

(defun or-null (value) (if (null value) json-null value))
(defun nullable (value) (if (json-null-p value) nil value))

(defun media-path (media)
  (media-file-path (media-space media) (media-id media) (media-mime media)))

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

(defun zip-to-octets (entries)
  "ENTRIES written as a zip, read back as octets. zippy writes to a file, so it
goes through a temporary one."
  (uiop:with-temporary-file (:pathname path :type "zip")
    (compress-zip (make-instance 'zip-file :entries (coerce entries 'vector))
                  path :if-exists :supersede)
    (with-open-file (in path :element-type '(unsigned-byte 8))
      (let ((octets (make-array (file-length in) :element-type '(unsigned-byte 8))))
        (read-sequence octets in)
        octets))))

(defun export-space (space)
  "The archive of SPACE as zip octets. Signals ARCHIVE-ERROR when a media file is
missing from the disk: an archive without it would not restore."
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
    (zip-to-octets
     (cons (make-instance 'zip-entry :file-name "space.json"
                                     :content (string-to-octets (to-json document) :encoding :utf-8))
           (loop :for m :in media
                 :for path := (media-path m)
                 :unless (probe-file path)
                   :do (fail "The file of ~a (~a) is missing from the media directory" (media-filename m) (media-id m))
                 ;; images are compressed already; deflating them again only costs time
                 :collect (make-instance 'zip-entry :file-name (media-entry-name (media-id m) (media-mime m))
                                                    :content path :compression-method :store))))))

;;; --- Import -------------------------------------------------------------------
;;;
;;; Read from a file, one entry at a time: an archive holds every media file of
;;; a space, and the heap is not the place for all of them at once.

(defun archive-entries (zip)
  (let ((entries (make-hash-table :test 'equal)))
    (loop :for entry :across (entries zip)
          :do (setf (gethash (file-name entry) entries) entry))
    entries))

(defun read-document (entries)
  (let ((json (or (gethash "space.json" entries) (fail "The archive has no space.json"))))
    (let ((document (handler-case (parse-json (octets-to-string (entry-to-vector json) :encoding :utf-8))
                      (error () (fail "space.json is not valid JSON")))))
      (unless (hash-table-p document) (fail "space.json must be an object"))
      (unless (eql (jget document "koyaExport") +archive-version+)
        (fail "Unsupported archive version ~s (expected ~a)" (jget document "koyaExport") +archive-version+))
      document)))

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
     (make-content :id id :space space :model model :published published :draft draft
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

(defun parse-media (object entries)
  "The media row as a plist with the zip :entry holding its file, which is
checked the way an upload is. The bytes are not kept: they are read again when
the file is written."
  (unless (hash-table-p object) (fail "Each media must be an object"))
  (let* ((id (string-field object "id" :required t))
         (mime (string-field object "mime" :required t)))
    (unless (scan +media-id-pattern+ id) (fail "~s is not a media id" id))
    (unless (image-extension mime) (fail "Media ~a is ~a, which is not an accepted image type" id mime))
    (let* ((entry (or (gethash (media-entry-name id mime) entries)
                      (fail "The archive has no file for media ~a" id)))
           (bytes (entry-to-vector entry)))
      (multiple-value-bind (sniffed width height) (sniff-image bytes)
        (unless (equal sniffed mime) (fail "The file of media ~a is not the ~a it says it is" id mime))
        (list :id id :mime mime :entry entry :size (length bytes) :width width :height height
              :filename (or (string-field object "filename") "upload")
              :alt (or (string-field object "alt") "")
              :created-at (string-field object "createdAt" :required t))))))

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

(defun write-media-files (space media written)
  "Write every file, pushing each path onto the list in the cons WRITTEN once it
is made, so a caller that fails later takes away only what this import made. A
file already there is an error, never replaced: it may be another import's."
  (dolist (m media)
    (let ((path (media-file-path space (getf m :id) (getf m :mime))))
      (ensure-directories-exist path)
      (when (probe-file path) (fail "The file of media ~a is already in the media directory" (getf m :id)))
      (entry-to-file path (getf m :entry) :if-exists :error :restore-attributes nil)
      (push path (car written)))))

(defun import-space (source &key (by *actor*))
  "Make the space in the archive SOURCE -- a pathname, or octets -- again: its
schema, contents with their history, and media. Returns the space's name.
Nothing is sent to its webhooks. Signals ARCHIVE-ERROR (or a schema error) and
changes nothing when the archive is malformed or the space is not empty."
  (multiple-value-bind (zip streams) (handler-case (open-zip-file source)
                                       (error () (fail "This file is not a zip archive")))
    (unwind-protect (import-from-zip zip :by by)
      (mapc #'close streams))))

(defun import-from-zip (zip &key by)
  (let* ((entries (archive-entries zip))
         (document (read-document entries))
         (space (string-field document "space" :required t))
         (schema (jobject->schema (jget document "schema"))))
    (unless (slug-name-p space) (fail "~s is not a space name" space))
    (check-target space)
    (import-into space schema
                 (map 'list (lambda (o) (parse-content o space schema))
                      (or (nullable (jget document "contents")) #()))
                 (map 'list (lambda (o) (parse-media o entries))
                      (or (nullable (jget document "media")) #()))
                 :secret (string-field document "webhookSecret")
                 :delivery-keys (parse-keys document "deliveryKeys")
                 :management-keys (parse-keys document "managementKeys")
                 :by by)))

(defun import-into (space schema contents media &key secret delivery-keys management-keys by)
  ;; the files first, as an upload does: a failed write must not leave rows
  ;; whose URLs 404; a failed transaction takes the files away again
  (let ((written (list '()))
        (done nil))
    (unwind-protect
         (progn
           (write-media-files space media written)
           (with-transaction
             ;; checked again inside: another import may have made it since
             (check-target space)
             (unless (find-space space) (insert-space space))
             (save-schema space schema :by by)
             (when secret (set-webhook-secret space secret))
             (dolist (k delivery-keys) (apply #'import-delivery-key space k))
             (dolist (k management-keys) (apply #'import-management-key space k))
             (dolist (m media)
               (insert-media space :id (getf m :id) :filename (getf m :filename) :mime (getf m :mime)
                                   :size (getf m :size) :width (getf m :width) :height (getf m :height)
                                   :alt (getf m :alt) :created-at (getf m :created-at)))
             (loop :for (content revisions) :in contents
                   :do (import-content content)
                       (dolist (r revisions)
                         (import-revision (content-id content) (getf r :event) (getf r :data)
                                          :by (getf r :by) :created-at (getf r :created-at)))))
           (setf done t))
      (unless done (mapc #'uiop:delete-file-if-exists (car written))))
    space))

;;; An archive sent as a request body is copied to a file and read from there,
;;; so it is never held in memory whole.

(defun copy-to-file (in path)
  "Copy IN to PATH, refusing more than the import limit: a chunked body has no
Content-Length for the middleware to check."
  (with-open-file (out path :direction :output :element-type '(unsigned-byte 8) :if-exists :supersede)
    (let ((buffer (make-array 65536 :element-type '(unsigned-byte 8))))
      (loop :for n := (read-sequence buffer in)
            :for total := n :then (+ total n)
            :while (plusp n)
            :do (when (> total +max-archive-bytes+)
                  (error "The archive is larger than ~a MB" (floor +max-archive-bytes+ (* 1024 1024))))
                (write-sequence buffer out :end n)))))

(defun import-space-stream (in &key (by *actor*))
  "IMPORT-SPACE for the archive read from the stream IN."
  (uiop:with-temporary-file (:pathname path :type "zip")
    (copy-to-file in path)
    (import-space path :by by)))
