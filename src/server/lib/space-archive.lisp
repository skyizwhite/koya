(defpackage #:koya-server/lib/space-archive
  (:use #:cl)
  (:import-from #:koya-server/db/connection
                #:with-db-transaction)
  (:import-from #:koya-server/db/schema-store
                #:load-schema #:save-schema #:find-space #:create-space)
  (:import-from #:koya-server/db/contents
                #:space-contents #:import-content #:make-content
                #:content-id #:content-model #:content-published #:content-draft #:content-draft-key
                #:content-created-at #:content-updated-at #:content-published-at #:content-revised-at)
  (:import-from #:koya-server/db/content-revisions
                #:content-history #:import-revision
                #:revision-event #:revision-data #:revision-by #:revision-created-at)
  (:import-from #:koya-server/db/media
                #:space-media #:insert-media
                #:media-id #:media-filename #:media-mime #:media-size
                #:media-width #:media-height #:media-alt #:media-created-at)
  (:import-from #:koya-server/lib/media-store
                #:media-path #:media-file-path)
  (:import-from #:koya-server/lib/image
                #:sniff-image #:image-extension)
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
           #:archive-file-name
           #:archive-error
           #:+max-archive-bytes+))
(in-package #:koya-server/lib/space-archive)

;;; A space as one zip: space.json -- the schema, every content with its draft,
;;; its system timestamps and its history, and the media rows -- plus the media
;;; files under media/. Keys and the webhook secret are left out: the file would
;;; otherwise be a credential. Importing makes the space again under the same
;;; name, with the same ids, so references, media fields and the /media/ paths in
;;; richtext keep pointing at the right things.

(defparameter +archive-version+ 1)

(defparameter +max-archive-bytes+ (* 512 1024 1024)
  "Largest archive /import accepts. It carries every media file of a space.")

(defparameter +media-id-pattern+ "^[0-9A-Z]{26}\\z"
  "What STORE-UPLOAD makes, and what /media/ serves. An archive's ids become file
names, so nothing else is accepted.")

(define-condition archive-error (error)
  ((message :initarg :message :reader archive-error-message))
  (:report (lambda (c s) (write-string (archive-error-message c) s))))

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
                            "media" (map 'vector #'media->jobject media))))
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

(defun check-target (space)
  "A space is imported only where it would not meet anything of its own: a name
that is free, or a space with no models yet (a content needs a model)."
  (let ((existing (and (find-space space) (load-schema space))))
    (when (and existing (schema-models existing))
      (fail "Space ~a already has models. Import into a space that has none, or delete it first." space))))

(defun write-media-files (space media written)
  "Write every file, pushing each path onto the list in the cons WRITTEN as it
goes, so a caller that fails later knows what to take away."
  (dolist (m media)
    (let ((path (media-file-path space (getf m :id) (getf m :mime))))
      (ensure-directories-exist path)
      (entry-to-file path (getf m :entry) :if-exists :supersede :restore-attributes nil)
      (push path (car written)))))

(defun import-space (source &key (by ""))
  "Make the space in the archive SOURCE -- a pathname, or octets -- again: its
schema, contents with their history, and media. Returns the space's name.
Nothing is sent to its webhooks. Signals ARCHIVE-ERROR (or a schema error) and
changes nothing when the archive is malformed or the space already has models."
  (multiple-value-bind (zip streams) (handler-case (open-zip-file source)
                                       (error () (fail "This file is not a zip archive")))
    (unwind-protect (import-from-zip zip :by by)
      (mapc #'close streams))))

(defun import-from-zip (zip &key by)
  (let* ((entries (archive-entries zip))
         (document (read-document entries))
         (space (string-field document "space" :required t))
         (schema (jobject->schema (jget document "schema")))
         (contents (map 'list (lambda (o) (parse-content o space schema))
                        (or (nullable (jget document "contents")) #())))
         (media (map 'list (lambda (o) (parse-media o entries))
                     (or (nullable (jget document "media")) #()))))
    (unless (slug-name-p space) (fail "~s is not a space name" space))
    (check-target space)
    ;; the files first, as an upload does: a failed write must not leave rows
    ;; whose URLs 404; a failed transaction takes the files away again
    (let ((written (list '()))
          (done nil))
      (unwind-protect
           (progn
             (write-media-files space media written)
             (with-db-transaction
               ;; checked again inside: another import may have made it since
               (check-target space)
               (unless (find-space space) (create-space space))
               (save-schema space schema :by by)
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
      space)))
