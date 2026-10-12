(defpackage #:koya-spec/server/web/pages/space-import
  (:use #:cl #:rove)
  (:import-from #:koya-server/domain/key #:key-id #:key-label #:hash-key)
  (:import-from #:koya-server/usecases/ports/keys #:insert-delivery-key)
  (:import-from #:koya-server/usecases/ports/deploys #:list-deploys)
  (:import-from #:koya-server/usecases/schema #:replace-schema)
  (:import-from #:koya-spec/server/web/pages/support
                #:moved-to #:post-login #:*secret* #:*cookie* #:request #:location #:setup-pages #:log-in)
  (:import-from #:koya-server/infra/db/connection #:disconnect-db)
  (:import-from #:koya-server/usecases/ports/spaces #:find-space #:delete-space #:load-schema
                #:space-webhooks #:space-webhook-secret)
  (:import-from #:koya-server/usecases/spaces #:create-space)
  (:import-from #:koya-server/usecases/keys
                #:create-delivery-key #:list-delivery-keys #:create-management-key
                #:space-for-delivery-key #:space-for-management-key)
  (:import-from #:koya-server/domain/content
                #:make-content #:content-status #:content-published #:content-draft #:content-id #:status-of
                #:content-draft-key #:content-created-at #:content-published-at)
  (:import-from #:koya-server/usecases/ports/media
                #:list-media #:media-file-path #:write-media-file #:delete-media-file #:insert-media)
  (:import-from #:koya-server/domain/media
                #:media-id #:media-filename #:media-space #:media-mime #:media-alt
                #:+max-upload-bytes+)
  (:import-from #:koya-spec/server/usecases/media #:png-bytes)
  (:import-from #:koya-spec/server/fake-webhooks #:*webhook-sender*)
  (:import-from #:koya-core/schema #:make-webhook)
  (:import-from #:koya-core/schema #:make-field #:make-model #:make-schema #:make-custom-field #:model-field #:model-fields #:field-type #:field-option)
  (:import-from #:org.shirakumo.zippy #:zip-file #:zip-entry #:compress-zip)
  (:import-from #:koya-core/ulid #:make-ulid)
  (:import-from #:koya-server/domain/deploy #:deploy-by)
  (:import-from #:koya-server/usecases/ports/contents
                #:list-revisions #:count-revisions #:get-content #:insert-content #:record-revision)
  (:import-from #:koya-server/usecases/ports/spaces #:find-model)
  (:import-from #:koya-server/usecases/contents #:create #:update-draft)
  (:import-from #:koya-server/usecases/webhooks #:*webhook-async*)
  (:import-from #:koya-server/domain/revision #:revision-event #:revision-created-at #:revision-data)
  (:import-from #:koya-core/data #:data-equal)
  (:import-from #:access #:access)
  (:import-from #:babel #:string-to-octets)
  (:import-from #:koya-server/usecases/media
                #:store-upload #:remove-space-media)
  (:import-from #:koya-core/schema #:schema-models #:model-name #:webhook-url)
  (:import-from #:koya-server/web/pages/index
                #:begin-import-action #:continue-import-action #:finish-import-action)
  (:import-from #:koya-server/infra/env #:archive-dir))
(in-package #:koya-spec/server/web/pages/space-import)

(setup (setup-pages) (log-in))

(teardown (disconnect-db))

(defun archive-schema ()
  (make-schema :webhooks (list (make-webhook "site" "https://site.test/hook"))
               :models (list (make-model "tag" :list (list (make-field :name :text)))
                             (make-model "post" :list (list (make-field :title :text)
                                                            (make-field :cover :media)
                                                            (make-field :body :richtext)
                                                            (make-field :tags :reference :model "tag" :many t))
                                         :label :title))))

(defparameter +from-the-page+ '(("origin" . "http://localhost:3000") ("nm-request" . "true")))

(defun post-piece (url &optional (octets (make-array 0 :element-type '(unsigned-byte 8))) (headers +from-the-page+))
  (let ((q (position #\? url)))
    (request :post (subseq url 0 q) :query (and q (subseq url (1+ q))) :headers headers
                                    :body octets :content-type "application/octet-stream")))

(defun begin ()
  (string-trim '(#\Space #\Newline) (nth-value 1 (post-piece (begin-import-action)))))

(defun piece-url (id offset)
  (format nil "~a?id=~a&offset=~a" (continue-import-action) id offset))

(defun import-archive (octets &key (pieces 3))
  (let ((id (begin))
        (size (max 1 (ceiling (length octets) pieces))))
    (loop :for offset :from 0 :below (length octets) :by size
          :do (post-piece (piece-url id offset) (subseq octets offset (min (length octets) (+ offset size)))))
    (multiple-value-bind (status body) (post-piece (format nil "~a?id=~a" (finish-import-action) id))
      (values status (moved-to body)))))

(defun declare-sizes (octets size)
  (let ((copy (copy-seq octets)))
    (flet ((put (at)
             (dotimes (i 4) (setf (aref copy (+ at i)) (ldb (byte 8 (* 8 i)) size)))))
      (loop :for i :from 0 :to (- (length copy) 4)
            :do (cond ((and (= (aref copy i) #x50) (= (aref copy (+ i 1)) #x4b)
                            (= (aref copy (+ i 2)) 3) (= (aref copy (+ i 3)) 4))
                       (put (+ i 22)))
                      ((and (= (aref copy i) #x50) (= (aref copy (+ i 1)) #x4b)
                            (= (aref copy (+ i 2)) 1) (= (aref copy (+ i 3)) 2))
                       (put (+ i 24))))))
    copy))

(defun archive-files (pattern)
  (let ((directory (archive-dir)))
    (and (uiop:directory-exists-p directory)
         (remove-if-not (lambda (file) (search pattern (file-namestring file)))
                        (uiop:directory-files directory)))))

(deftest a-space-is-exported-and-imported-again

  (let ((*webhook-async* nil)
        (*webhook-sender* (lambda (&rest args) (declare (ignore args)) (values 200 "" nil))))
  (setf *cookie* nil)
  (post-login :form `(("secret" . ,*secret*)))
  (create-space "archive")
  (replace-schema "archive" (archive-schema))
  (let* ((media (store-upload "archive" (png-bytes 4 5) :filename "cover.png" :alt "A cover"))
         (tag (progn (insert-content (make-content :id "tag-1" :space "archive" :model "tag" :status "published"
                                                   :published (list :name "lisp")
                                                   :created-at "2020-01-01T00:00:00.000Z" :updated-at "2020-01-02T00:00:00.000Z"
                                                   :published-at "2020-01-02T00:00:00.000Z" :revised-at "2020-01-02T00:00:00.000Z")
                                     nil nil)
                     (record-revision "archive" "tag-1" "publish" (list :name "lisp")
                                      :created-at "2020-01-02T00:00:00.000Z")
                     "tag-1"))
         (post (content-id (create "archive" (find-model "archive" "post")
                                           (list :title "Old" :cover (media-id media) :tags (vector tag))
                                           :publish t)))
         (old-secret (space-webhook-secret "archive"))
         (delivery-key (create-delivery-key "archive" :label "site"))
         (delivery-key-id (key-id (first (list-delivery-keys "archive"))))
         (management-key (create-management-key "archive" :label "repl"))
         (sent 0)
         octets)
    (update-draft "archive" (find-model "archive" "post") post
                  (list :title "New"
                        :body (format nil "<p><img src=\"/media/archive/~a.png\"></p>" (media-id media)))
                  :replace t)
    (testing "the space page offers the export"
      (let ((body (nth-value 1 (request :get "/s/archive"))))
        (ok (search "href=\"/s/archive/export\"" body))
        (ng (search "download" body) "a failed export must show its toast, not be saved as a file")))
    (testing "export is a zip download"
      (multiple-value-bind (status body headers) (request :get "/s/archive/export")
        (ok (= status 200))
        (ok (string= (getf headers :content-type) "application/zip"))
        (ok (search "attachment; filename=\"archive-" (getf headers :content-disposition)))
        (ok (typep body '(vector (unsigned-byte 8))))
        (ok (equalp (subseq body 0 2) #(80 75)) "PK")
        (setf octets body)))
    (delete-space "archive")
    (remove-space-media "archive")
    (let ((*webhook-sender* (lambda (url payload headers)
                              (declare (ignore url payload headers))
                              (incf sent))))
      (testing "import makes the space again"
        (multiple-value-bind (status location) (import-archive octets)
          (ok (= status 200))
          (ok (string= location "/s/archive")))
        (ok (search "Space archive imported." (nth-value 1 (request :get "/s/archive"))))
        (ok (equal (mapcar #'model-name (schema-models (load-schema "archive"))) '("tag" "post")))
        (ok (equal (mapcar #'webhook-url (space-webhooks "archive")) '("https://site.test/hook"))
            "with its webhooks")
        (ok (string= (space-webhook-secret "archive") old-secret)
            "and its webhook secret, which the site checks")
        (ok (= sent 0) "and nothing is sent to them"))
      (testing "the site's keys still work"
        (ok (string= (space-for-delivery-key delivery-key) "archive"))
        (ok (string= (space-for-management-key management-key) "archive"))
        (ok (equal (mapcar #'key-label (list-delivery-keys "archive")) '("site"))))
      (testing "contents keep their ids, state, draft, timestamps and history"
        (let ((tag-content (get-content "archive" tag))
              (post-content (get-content "archive" post)))
          (ok tag-content "an id given before koya made them all is kept too")
          (let ((history (list-revisions "archive" tag)))
            (ok (equal (mapcar #'revision-event history) '("publish")) "with its history")
            (ok (string= (revision-created-at (first history)) "2020-01-02T00:00:00.000Z") "dated as it was"))
          (ok (string= (content-created-at tag-content) "2020-01-01T00:00:00.000Z"))
          (ok (string= (content-published-at tag-content) "2020-01-02T00:00:00.000Z"))
          (ok (string= (content-status post-content) "published+draft"))
          (ok (string= (access (content-published post-content) :title) "Old"))
          (ok (string= (access (content-draft post-content) :title) "New"))
          (ok (equalp (access (content-published post-content) :tags) (vector tag)))
          (ok (content-draft-key post-content) "the preview link still works")
          (ok (= (count-revisions "archive" post) 2))
          (ok (equal (mapcar #'revision-event (list-revisions "archive" post)) '("draft" "publish")))))
      (testing "media keep their ids, metadata and files"
        (let ((copy (find (media-id media) (list-media "archive") :key #'media-id :test #'string=)))
          (ok copy)
          (ok (string= (media-filename copy) "cover.png"))
          (ok (string= (media-alt copy) "A cover"))
          (ok (equalp (alexandria:read-file-into-byte-vector (media-file-path (media-space copy) (media-id copy) (media-mime copy))) (png-bytes 4 5)))))
      (testing "the import is in the deploy log, named for whoever made it"
        (ok (equal (mapcar #'deploy-by (list-deploys "archive")) '("owner"))))
      (testing "a space that has models is not imported into"
        (multiple-value-bind (status location) (import-archive octets)
          (ok (= status 200))
          (ok (string= location "/")))
        (ok (search "is not empty" (nth-value 1 (request :get "/"))))
        (ok (= (length (list-deploys "archive")) 1) "and nothing changed"))
      (testing "a space whose models went but whose media stayed is not empty"
        (replace-schema "archive" (make-schema))
        (let ((path (let ((m (find (media-id media) (list-media "archive") :key #'media-id :test #'string=)))
                      (media-file-path (media-space m) (media-id m) (media-mime m)))))
          (multiple-value-bind (status location) (import-archive octets)
            (ok (= status 200))
            (ok (string= location "/")))
          (ok (search "is not empty" (nth-value 1 (request :get "/"))))
          (ok (probe-file path) "its file is still there")
          (ok (find (media-id media) (list-media "archive") :key #'media-id :test #'string=))))
      (testing "nor is one that has only a key"
        (delete-space "archive")
        (remove-space-media "archive")
        (create-space "archive")
        (create-delivery-key "archive")
        (ok (string= (nth-value 1 (import-archive octets)) "/"))
        (ok (search "is not empty" (nth-value 1 (request :get "/"))))
        (ng (get-content "archive" post)))
      (testing "one that has only webhooks is imported into, and they are replaced"
        (delete-space "archive")
        (remove-space-media "archive")
        (create-space "archive")
        (replace-schema "archive" (make-schema :webhooks (list (make-webhook "old" "https://old.test/hook"))))
        (ok (string= (nth-value 1 (import-archive octets)) "/s/archive"))
        (ok (get-content "archive" post))
        (ok (equal (mapcar #'webhook-url (space-webhooks "archive")) '("https://site.test/hook")))
        (ok (string= (space-webhook-secret "archive") old-secret))))
    (testing "a file that is not an archive changes nothing"
      (delete-space "archive")
      (remove-space-media "archive")
      (multiple-value-bind (status location) (import-archive (string-to-octets "not a zip"))
        (ok (= status 200))
        (ok (string= location "/")))
      (ok (search "not a zip archive" (nth-value 1 (request :get "/"))))
      (ng (find-space "archive")))
    (testing "a file already in the library is never replaced, and the import changes nothing"
      (write-media-file "archive" (media-id media) "image/png" (png-bytes 1 1))
      (ok (string= (nth-value 1 (import-archive octets)) "/"))
      (ok (search "already in the media library" (nth-value 1 (request :get "/"))))
      (ng (find-space "archive"))
      (ok (equalp (alexandria:read-file-into-byte-vector (media-file-path "archive" (media-id media) "image/png"))
                  (png-bytes 1 1))
          "the file that was there is as it was")
      (remove-space-media "archive"))
    (testing "a space whose file has gone is not exported, and says why"
      (ok (string= (nth-value 1 (import-archive octets)) "/s/archive"))
      (delete-media-file "archive" (media-id media) "image/png")
      (multiple-value-bind (status body headers) (request :get "/s/archive/export")
        (declare (ignore body))
        (ok (= status 303))
        (ok (string= (getf headers :location) "/s/archive")))
      (ok (search "missing from the media library" (nth-value 1 (request :get "/s/archive"))))
      (delete-space "archive")
      (remove-space-media "archive"))
    (testing "pieces go where they say, in order"
      (let ((id (begin)))
        (ok (= 409 (post-piece (piece-url id 5) (subseq octets 0 5))) "one that skips ahead is refused")
        (ok (search "has 0 bytes" (nth-value 1 (post-piece (piece-url id 5) (subseq octets 0 5))))
            "and says where the import stands")
        (ok (= 409 (request :post (continue-import-action) :query (format nil "id=~a" id) :headers +from-the-page+
                            :multipart (list (list "offset" "offset.txt" "text/plain" (string-to-octets "0")))))
            "one whose offset is a file is refused too")
        (ok (= 409 (post-piece (piece-url id "abc") (subseq octets 0 5))) "and one whose offset is not a number")
        (ok (= 200 (post-piece (piece-url id 0) (subseq octets 0 5))))
        (ok (= 409 (post-piece (piece-url id 0) (subseq octets 0 5))) "one sent twice is refused")
        (ok (string= (string-trim '(#\Space) (nth-value 1 (post-piece (piece-url id 5) (subseq octets 5 9))))
                     "9")
            "the next one is taken, and the answer is how much has arrived")))
    (testing "an import that was never begun is not found"
      (ok (= 404 (post-piece (piece-url "01ARZ3NDEKTSV4RRFFQ69G5FAV" 0) (subseq octets 0 5))))
      (ok (= 404 (post-piece (piece-url "../../etc/passwd" 0) (subseq octets 0 5))) "nor is a path"))
    (testing "an import is gone once it is finished, and one given up is cleared a day later"
      (let ((stale (begin))
            (count (length (archive-files ".upload"))))
        (sb-posix:utime (merge-pathnames (format nil "~a.upload" stale) (archive-dir))
                        (- (get-universal-time) #.(encode-universal-time 0 0 0 1 1 1970 0) (* 2 24 3600))
                        (- (get-universal-time) #.(encode-universal-time 0 0 0 1 1 1970 0) (* 2 24 3600)))
        (ok (string= (nth-value 1 (import-archive (string-to-octets "not a zip"))) "/"))
        (ok (null (archive-files stale)) "the one given up a day ago is gone")
        (ok (= (length (archive-files ".upload")) (1- count)) "and so is the one just finished")))
    (testing "an entry larger than its headers say is refused, and nothing is written past them"
      (ok (string= (nth-value 1 (import-archive (declare-sizes octets 10))) "/"))
      (ok (search "is not the size its headers say" (nth-value 1 (request :get "/"))))
      (ng (find-space "archive")))
    (testing "an entry whose headers claim a huge size is refused before anything is made for it"
      (ok (string= (nth-value 1 (import-archive (declare-sizes octets #xfffffff0))) "/"))
      (ok (search "larger than" (nth-value 1 (request :get "/"))))
      (ng (find-space "archive")))
    (testing "a file larger than an upload may be is refused before it is read"
      (let ((+max-upload-bytes+ 10))
        (declare (special +max-upload-bytes+))
        (ok (string= (nth-value 1 (import-archive octets)) "/")))
      (ok (search "larger than an upload may be" (nth-value 1 (request :get "/"))))
      (ng (find-space "archive")))
    (testing "a transaction that fails takes away the files it wrote"
      (create-space "clash")
      (insert-delivery-key "clash" :id delivery-key-id :hash (hash-key "another key")
                                   :label "" :created-at "2020-01-01T00:00:00.000Z")
      (ok (string= (nth-value 1 (import-archive octets)) "/"))
      (ng (find-space "archive"))
      (ng (probe-file (media-file-path "archive" (media-id media) "image/png")))
      (delete-space "clash"))
    (testing "an export leaves nothing behind"
      (ok (string= (nth-value 1 (import-archive octets)) "/s/archive"))
      (ok (= 200 (request :get "/s/archive/export")))
      (ok (null (archive-files "export-")) "the archive is deleted once it is sent")
      (delete-space "archive")
      (remove-space-media "archive"))
    (testing "an import from another site is refused"
      (ok (= 403 (post-piece (begin-import-action) nil '(("origin" . "https://evil.test") ("nm-request" . "true")))))
      (ok (= 400 (post-piece (begin-import-action) nil '(("origin" . "http://localhost:3000"))))
          "nor is a plain post: an action answers the admin UI only")
      (ng (find-space "archive")))
    (testing "the import dialog is on the spaces page"
      (let ((page (nth-value 1 (request :get "/"))))
        (ok (search "nm-data=\"...koya.importer(this)\"" page) "the form holds how far the import is")
        (ok (search (format nil "data-import-begin=\"~a\"" (begin-import-action)) page))
        (ok (search "data-import-piece-bytes=" page))
        (ok (search "nm-bind=\"{ href: () => _login }\"" page)
            "and the dialog, which hides the page's toast, has its own way to log in again"))))))

(deftest an-import-refuses-a-content-id-the-admin-ui-cannot-open
  (setf *cookie* nil)
  (post-login :form `(("secret" . ,*secret*)))
  (loop :for (id . shown) :in '(("new" . "&quot;new&quot;") ("a/b" . "&quot;a&#x2F;b&quot;"))
        :do (create-space "odd")
            (replace-schema "odd" (make-schema :models (list (make-model "tag" :list (list (make-field :name :text))))))
            (insert-content (make-content :id id :space "odd" :model "tag" :status "published"
                                          :published (list :name "x")
                                          :created-at "2024-01-01T00:00:00.000Z" :updated-at "2024-01-01T00:00:00.000Z"
                                          :published-at "2024-01-01T00:00:00.000Z" :revised-at "2024-01-01T00:00:00.000Z")
                            nil nil)
            (let ((octets (nth-value 1 (request :get "/s/odd/export"))))
              (delete-space "odd")
              (ok (string= (nth-value 1 (import-archive octets)) "/"))
              (ok (search (format nil "~a is not a content id" shown) (nth-value 1 (request :get "/")))
                  (format nil "~s is refused, and the toast names it" id))
              (ng (find-space "odd") "and nothing is imported"))))

(defun odd-archive (&key contents media key revisions
                         (schema (make-schema :models (list (make-model "tag" :list (list (make-field :name :text :required t :unique t)))))))
  (create-space "odd")
  (replace-schema "odd" schema)
  (dolist (c contents)
    (insert-content (apply #'make-content (append c (list :space "odd" :model "tag"
                                                          :status (status-of (and (member :published c) t)
                                                                             (and (member :draft c) t))
                                                          :created-at "2024-01-01T00:00:00.000Z"
                                                          :updated-at "2024-01-01T00:00:00.000Z")))
                    nil nil))
  (loop :for (id data) :in revisions
        :do (record-revision "odd" id "draft" data :created-at "2024-01-01T00:00:00.000Z"))
  (let ((stored (and media (store-upload "odd" (png-bytes 2 2) :filename "a.png")))
        (made (and key (create-delivery-key "odd" :label "site"))))
    (let ((octets (nth-value 1 (request :get "/s/odd/export"))))
      (delete-space "odd")
      (remove-space-media "odd")
      (values octets stored made))))

(defun tag (name) (list :name name))

(defun refusal (octets)
  (and (string= (nth-value 1 (import-archive octets)) "/")
       (not (find-space "odd"))
       (let* ((page (nth-value 1 (request :get "/")))
              (at (search "Import failed: " page)))
         (and at (subseq page (+ at 15) (search "<" page :start2 at))))))

(deftest an-import-holds-what-it-writes-to-the-schema-it-brings
  (setf *cookie* nil)
  (post-login :form `(("secret" . ,*secret*)))
  (testing "a content that does not fit its model is refused, named"
    (ok (equal (refusal (odd-archive :contents (list (list :id "t1" :draft nil))))
               "Content t1: name is required")))
  (testing "nor two that share a unique value"
    (ok (equal (refusal (odd-archive :contents (list (list :id "t1" :draft (tag "lisp"))
                                                     (list :id "t2" :draft (tag "lisp")))))
               "Content t1: name must be unique")))
  (testing "a published content needs the dates of its publishing"
    (ok (equal (refusal (odd-archive :contents (list (list :id "t1" :published (tag "lisp")))))
               "Content t1: publishedAt must be an ISO 8601 datetime with a date, a time and a zone")))
  (testing "a timestamp without a zone is refused"
    (ok (equal (refusal (odd-archive :contents (list (list :id "t1" :draft (tag "lisp") :created-at "2024-01-01"))))
               "Content t1: createdAt must be an ISO 8601 datetime with a date, a time and a zone")))
  (testing "one with a zone is kept in UTC"
    (ok (string= (nth-value 1 (import-archive
                               (odd-archive :contents (list (list :id "t1" :draft (tag "lisp")
                                                                  :created-at "2024-01-01T10:00+09:00")))))
                 "/s/odd"))
    (ok (string= (content-created-at (get-content "odd" "t1")) "2024-01-01T01:00:00.000Z"))
    (delete-space "odd"))
  (testing "a media or a key another space holds is named before anything is written"
    (multiple-value-bind (octets stored) (odd-archive :media t)
      (create-space "elsewhere")
      (insert-media "elsewhere" :id (media-id stored) :filename "b.png" :mime "image/png" :size 1
                                :width 1 :height 1 :alt "" :created-at "2024-01-01T00:00:00.000Z")
      (ok (equal (refusal octets) (format nil "Media ~a is already in another space" (media-id stored))))
      (delete-space "elsewhere"))
    (multiple-value-bind (octets stored key) (odd-archive :key t)
      (declare (ignore stored))
      (create-space "elsewhere")
      (insert-delivery-key "elsewhere" :id "01ARZ3NDEKTSV4RRFFQ69G5FAZ" :hash (hash-key key)
                                       :label "" :created-at "2024-01-01T00:00:00.000Z")
      (ok (equal (refusal octets) "A key in the archive is already a key of another space"))
      (delete-space "elsewhere"))))

(defun zip-of (name octets)
  (let ((path (merge-pathnames (format nil "spec-~a.zip" (make-ulid)) (archive-dir))))
    (ensure-directories-exist path)
    (compress-zip (make-instance 'zip-file :entries (vector (make-instance 'zip-entry :file-name name :content octets)))
                  path :if-exists :supersede)
    path))

(defun legacy-archive ()
  (archive-of "{\"koyaExport\": 1, \"space\": \"legacy\",
              \"schema\": {\"koyaSchema\": 1, \"webhooks\": [],
                           \"models\": [{\"name\": \"post\", \"kind\": \"list\",
                                         \"fields\": [{\"name\": \"title\", \"type\": \"text\", \"unique\": true},
                                                      {\"name\": \"slug\", \"type\": \"slug\", \"from\": \"title\", \"unique\": true}]},
                                        {\"name\": \"page\", \"kind\": \"list\",
                                         \"fields\": [{\"name\": \"slug\", \"type\": \"slug\", \"from\": \"path\"},
                                                      {\"name\": \"path\", \"type\": \"slug\", \"from\": \"slug\"}]}]},
              \"contents\": [{\"id\": \"p1\", \"model\": \"post\", \"draft\": {\"title\": \"One\", \"slug\": \"one\"},
                              \"createdAt\": \"2024-01-01T00:00:00.000Z\", \"updatedAt\": \"2024-01-01T00:00:00.000Z\"},
                             {\"id\": \"g1\", \"model\": \"page\", \"draft\": {\"slug\": \"same\", \"path\": \"a\"},
                              \"createdAt\": \"2024-01-01T00:00:00.000Z\", \"updatedAt\": \"2024-01-01T00:00:00.000Z\"},
                             {\"id\": \"g2\", \"model\": \"page\", \"draft\": {\"slug\": \"same\", \"path\": \"a\"},
                              \"createdAt\": \"2024-01-01T00:00:00.000Z\", \"updatedAt\": \"2024-01-01T00:00:00.000Z\"}]}"))

(defun read-file-bytes (path)
  (with-open-file (in path :element-type '(unsigned-byte 8))
    (let ((octets (make-array (file-length in) :element-type '(unsigned-byte 8))))
      (read-sequence octets in)
      octets)))

(deftest an-archive-from-before-slugs-were-typed-is-imported
  (setf *cookie* nil)
  (post-login :form `(("secret" . ,*secret*)))
  (ok (string= (nth-value 1 (import-archive (legacy-archive))) "/s/legacy")
      "its slug fields lose what a slug no longer takes")
  (let ((post (find-model "legacy" "post")))
    (ok (eq (field-type (model-field post :slug)) :slug))
    (ok (field-option (model-field post :title) :unique) "a text field keeps its unique"))
  (ok (string= (access (content-draft (get-content "legacy" "p1")) :slug) "one") "and its contents come with it")
  (testing "what the server keeps from before slugs were keys, it takes back from an archive"
    (ok (= (length (model-fields (find-model "legacy" "page"))) 2) "a model with two slug fields")
    (ok (and (get-content "legacy" "g1") (get-content "legacy" "g2")) "and two contents that share a slug"))
  (delete-space "legacy"))

(deftest an-import-keeps-of-each-revision-what-fits-its-fields-types
  (setf *cookie* nil)
  (post-login :form `(("secret" . ,*secret*)))
  (let ((schema (make-schema :custom-fields (list (make-custom-field "heading" (list (make-field :text :text :max-length 3)))
                                                  (make-custom-field "quote" (list (make-field :text :text))))
                             :models (list (make-model "tag" :list
                                                       (list (make-field :name :text :required t :unique t)
                                                             (make-field :rank :number)
                                                             (make-field :blocks :repeater :custom-fields '(heading))))))))
    (ok (string= (nth-value 1 (import-archive
                               (odd-archive :schema schema
                                            :contents (list (list :id "t1" :draft (tag "lisp"))
                                                            (list :id "t2" :draft (tag "lisp2")))
                                            :revisions (list (list "t1" (list :name 3 :rank "first" :gone "x"
                                                                              :blocks (vector (list :field-id "quote" :text "Q")
                                                                                              (list :field-id "heading" :text "Long" :rank 1))))
                                                             (list "t2" (list :rank 2))))))
                 "/s/odd")
        "a revision that does not fit is imported")
    (ok (data-equal (revision-data (first (list-revisions "odd" "t1")))
                    (list :blocks (vector (list :text "Long" :field-id "heading"))))
        "without a value not of its field's type, a key that is not a field, or a row of a custom field its repeater does not list")
    (ok (data-equal (revision-data (first (list-revisions "odd" "t2"))) (list :rank 2))
        "and one that misses what the model asks of its values now is kept as it is")
    (delete-space "odd")))

(deftest an-empty-version-moves-with-its-space
  (setf *cookie* nil)
  (post-login :form `(("secret" . ,*secret*)))
  (let ((schema (make-schema :models (list (make-model "tag" :list (list (make-field :name :text)))))))
    (ok (string= (nth-value 1 (import-archive
                               (odd-archive :schema schema
                                            :contents (list (list :id "t1" :published nil
                                                                  :published-at "2024-01-01T00:00:00.000Z"
                                                                  :revised-at "2024-01-01T00:00:00.000Z")))))
                 "/s/odd"))
    (ok (string= (content-status (get-content "odd" "t1")) "published")
        "a published version with no values is published still")
    (delete-space "odd")))

(defun archive-of (json)
  (let ((path (zip-of "space.json" (string-to-octets json :encoding :utf-8))))
    (prog1 (read-file-bytes path) (delete-file path))))

(defun tag-archive (space rest)
  (archive-of (format nil "{\"koyaExport\": 1, \"space\": \"~a\",
                            \"schema\": {\"koyaSchema\": 1, \"models\": [{\"name\": \"tag\", \"kind\": \"list\",
                                                                      \"fields\": [{\"name\": \"name\", \"type\": \"text\"}]}]},
                            ~a}"
                      space rest)))

(deftest a-version-written-as-false-is-none
  (setf *cookie* nil)
  (post-login :form `(("secret" . ,*secret*)))
  (ok (string= (nth-value 1 (import-archive
                             (tag-archive "falsy" "\"contents\": [{\"id\": \"t1\", \"model\": \"tag\", \"published\": false, \"draft\": {\"name\": \"x\"},
                                                                    \"createdAt\": \"2024-01-01T00:00:00.000Z\", \"updatedAt\": \"2024-01-01T00:00:00.000Z\"}]")))
               "/s/falsy"))
  (ok (string= (content-status (get-content "falsy" "t1")) "draft") "a published version of false is none, as null is")
  (delete-space "falsy")
  (ok (string= (nth-value 1 (import-archive
                             (one-tag-archive "[{\"event\": \"draft\", \"data\": false, \"createdAt\": \"2024-01-01T00:00:00.000Z\"}]")))
               "/"))
  (ok (search "A revision of content t1 has no data" (nth-value 1 (request :get "/")))
      "and a revision whose data is false has none")
  (ng (find-space "falsy")))

(defun one-tag-archive (revisions)
  (tag-archive "falsy" (format nil "\"contents\": [{\"id\": \"t1\", \"model\": \"tag\", \"draft\": {\"name\": \"x\"},
                                                     \"createdAt\": \"2024-01-01T00:00:00.000Z\", \"updatedAt\": \"2024-01-01T00:00:00.000Z\",
                                                     \"revisions\": ~a}]"
                                   revisions)))

(deftest the-revisions-of-a-content-are-an-array
  (setf *cookie* nil)
  (post-login :form `(("secret" . ,*secret*)))
  (ok (string= (nth-value 1 (import-archive (one-tag-archive "[{\"event\": \"draft\", \"data\": {}, \"createdAt\": \"2024-01-01T00:00:00.000Z\"}]")))
               "/s/falsy"))
  (ok (null (revision-data (first (list-revisions "falsy" "t1")))) "a revision with no values is one, as an export writes it")
  (delete-space "falsy")
  (ok (string= (nth-value 1 (import-archive (one-tag-archive "false"))) "/s/falsy") "false is no revisions, as null is")
  (ok (zerop (count-revisions "falsy" "t1")))
  (delete-space "falsy")
  (ok (string= (nth-value 1 (import-archive (one-tag-archive "{}"))) "/"))
  (ok (search "The revisions of content t1 must be an array" (nth-value 1 (request :get "/")))
      "and an object is not an array")
  (ng (find-space "falsy")))

(deftest what-an-archive-lists-is-an-array
  (setf *cookie* nil)
  (post-login :form `(("secret" . ,*secret*)))
  (flet ((archive (key value)
           (tag-archive "lists" (format nil "\"~a\": ~a" key value))))
    (dolist (key '("contents" "media" "deliveryKeys" "managementKeys"))
      (ok (string= (nth-value 1 (import-archive (archive key "null"))) "/s/lists")
          (format nil "~a of null is none" key))
      (delete-space "lists")
      (ok (string= (nth-value 1 (import-archive (archive key "false"))) "/s/lists")
          (format nil "~a of false is none, as null is" key))
      (delete-space "lists")
      (ok (string= (nth-value 1 (import-archive (archive key "{}"))) "/"))
      (ok (search (format nil "~a must be an array" key) (nth-value 1 (request :get "/")))
          (format nil "and ~a of an object is refused" key))
      (ng (find-space "lists")))))
