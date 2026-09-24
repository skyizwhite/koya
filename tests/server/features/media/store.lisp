(defpackage #:koya-tests/server/features/media/store
  (:use #:cl #:rove)
  (:import-from #:koya-server/db/connection #:connect-db #:disconnect-db)
  (:import-from #:koya-server/db/migrations #:migrate)
  (:import-from #:koya-server/db/schema-store #:save-schema #:create-space #:delete-space)
  (:import-from #:koya-server/db/contents #:create-content)
  (:import-from #:koya-server/features/media/image #:sniff-image)
  (:import-from #:koya-server/features/media/store
                #:store-upload #:remove-media #:remove-space-media #:media-path #:media-url #:media->jobject)
  (:import-from #:koya-server/db/media
                #:find-media #:list-media #:count-media #:update-media #:media-references #:media-reference-counts
                #:media-id #:media-filename #:media-mime #:media-width #:media-height #:media-alt)
  (:import-from #:koya-server/lib/http #:api-error #:api-error-status)
  (:import-from #:koya/core/schema #:make-field #:make-model #:make-schema)
  (:import-from #:koya/core/json #:jget #:parse-json)
  (:import-from #:babel #:string-to-octets)
  (:export #:png-bytes #:*media-root* #:multipart-body))
(in-package #:koya-tests/server/features/media/store)

(defvar *media-root*
  (uiop:ensure-directory-pathname
   (format nil "~a/koya-test-media-~a/" (or (uiop:getenv "TMPDIR") "/tmp") (get-universal-time))))

(defun bytes (&rest list) (coerce list '(vector (unsigned-byte 8))))

(defun png-bytes (&optional (width 3) (height 2))
  "A PNG signature and IHDR chunk: enough for the sniffer, not a whole image."
  (flet ((be32 (n) (list (ldb (byte 8 24) n) (ldb (byte 8 16) n) (ldb (byte 8 8) n) (ldb (byte 8 0) n))))
    (apply #'bytes (append '(#x89 #x50 #x4E #x47 #x0D #x0A #x1A #x0A) (be32 13) '(#x49 #x48 #x44 #x52)
                           (be32 width) (be32 height) '(8 6 0 0 0)))))

(defun multipart-body (parts)
  "PARTS: (name value) for text fields or (name filename content-type octets) for files.
Returns (values octets content-type)."
  (let* ((boundary "----koyatest")
         (crlf (string-to-octets (format nil "~c~c" #\Return #\Linefeed)))
         (chunks '()))
    (flet ((text (s) (push (string-to-octets s :encoding :utf-8) chunks))
           (raw (o) (push o chunks)))
      (dolist (part parts)
        (text (format nil "--~a" boundary)) (raw crlf)
        (if (= (length part) 2)
            (progn (text (format nil "Content-Disposition: form-data; name=\"~a\"" (first part))) (raw crlf) (raw crlf)
                   (text (second part)) (raw crlf))
            (destructuring-bind (name filename content-type octets) part
              (text (format nil "Content-Disposition: form-data; name=\"~a\"; filename=\"~a\"" name filename)) (raw crlf)
              (text (format nil "Content-Type: ~a" content-type)) (raw crlf) (raw crlf)
              (raw octets) (raw crlf))))
      (text (format nil "--~a--" boundary)) (raw crlf))
    (values (apply #'concatenate '(vector (unsigned-byte 8)) (nreverse chunks))
            (format nil "multipart/form-data; boundary=~a" boundary))))

(setup
  (setf (uiop:getenv "KOYA_MEDIA_DIR") (namestring *media-root*))
  (connect-db ":memory:")
  (migrate)
  (create-space "website")
  (save-schema "website"
               (make-schema :models (list (make-model "blog" :list (list (make-field :title :text)
                                                                         (make-field :cover :media)
                                                                         (make-field :body :richtext)))))))

(teardown
  (disconnect-db)
  (uiop:delete-directory-tree *media-root* :validate t :if-does-not-exist :ignore))

(deftest sniffing
  (multiple-value-bind (mime w h) (sniff-image (png-bytes 640 480))
    (ok (string= mime "image/png")) (ok (= w 640)) (ok (= h 480)))
  (multiple-value-bind (mime w h) (sniff-image (bytes #x47 #x49 #x46 #x38 #x39 #x61 #x10 #x00 #x08 #x00 0))
    (ok (string= mime "image/gif")) (ok (= w 16)) (ok (= h 8)))
  (multiple-value-bind (mime w h)
      ;; SOI, then an SOF0 segment: FF C0, length 17, precision 8, height 0x0100, width 0x0080
      (sniff-image (bytes #xFF #xD8 #xFF #xC0 #x00 #x11 #x08 #x01 #x00 #x00 #x80 #x03 0 0 0 0 0 0 0 0))
    (ok (string= mime "image/jpeg")) (ok (= w 128)) (ok (= h 256)))
  (multiple-value-bind (mime w h)
      ;; RIFF size WEBP "VP8 " size, frame tag(3) start code(3) then width/height 14 bits each
      (sniff-image (bytes #x52 #x49 #x46 #x46 0 0 0 0 #x57 #x45 #x42 #x50 #x56 #x50 #x38 #x20 0 0 0 0
                          0 0 0 #x9D #x01 #x2A #x40 #x01 #xF0 #x00))
    (ok (string= mime "image/webp")) (ok (= w 320)) (ok (= h 240)))
  (ok (null (sniff-image (bytes #x3C #x73 #x76 #x67))) "svg is not accepted")
  (ok (null (sniff-image (bytes))) "empty")
  (multiple-value-bind (mime w) (sniff-image (bytes #x89 #x50 #x4E #x47 #x0D #x0A #x1A #x0A))
    (ok (string= mime "image/png")) (ok (null w) "truncated header gives no size")))

(deftest store-and-remove
  (let ((media (store-upload "website" (png-bytes 10 20) :filename "../evil/../photo.png" :alt "A photo")))
    (ok (string= (media-filename media) "photo.png") "directory parts are stripped from the name")
    (ok (string= (media-mime media) "image/png"))
    (ok (= (media-width media) 10))
    (ok (= (media-height media) 20))
    (ok (probe-file (media-path media)) "file written")
    (ok (search (format nil "/media/website/~a.png" (media-id media)) (media-url media)))
    (ok (string= (media-url media :absolute nil) (format nil "/media/website/~a.png" (media-id media))))
    (let ((obj (media->jobject media)))
      (ok (string= (jget obj "alt") "A photo"))
      (ok (= (jget obj "width") 10)))
    (testing "listing, search and alt"
      (store-upload "website" (png-bytes) :filename "other.png")
      (ok (= (count-media "website") 2))
      (ok (= (length (list-media "website" :search "pho")) 1))
      (ok (= (count-media "website" :search "%") 0) "LIKE wildcards are escaped")
      (ok (string= (media-alt (update-media "website" (media-id media) :alt "Changed")) "Changed")))
    (testing "references"
      (ok (= (media-references "website" (media-id media)) 0))
      (create-content "website" "blog" (parse-json (format nil "{\"title\": \"x\", \"cover\": \"~a\"}" (media-id media))))
      (create-content "website" "blog" (parse-json (format nil "{\"title\": \"y\", \"body\": \"<img src=\\\"~a\\\">\"}" (media-url media))))
      (ok (= (media-references "website" (media-id media)) 2) "field values and richtext URLs both count")
      (ok (= (gethash (media-id media) (media-reference-counts "website" (list (media-id media)))) 2)
          "the library's counts agree"))
    (testing "only the fields in the schema count"
      (koya-server/db/connection:exec "DELETE FROM contents")
      (create-content "website" "blog" (parse-json (format nil "{\"title\": \"~a\"}" (media-id media))))
      (ok (= (media-references "website" (media-id media)) 0) "a text field mentioning the id is not a use")
      (create-content "website" "blog" (parse-json (format nil "{\"title\": \"z\", \"cover\": \"~a\"}" (media-id media))))
      (ok (= (media-references "website" (media-id media)) 1))
      (save-schema "website" (make-schema :models (list (make-model "blog" :list (list (make-field :title :text)
                                                                                         (make-field :body :richtext))))))
      (ok (= (media-references "website" (media-id media)) 0) "a field removed by a deploy leaves its value unread")
      (ok (= (gethash (media-id media) (media-reference-counts "website" (list (media-id media)))) 0))
      (save-schema "website" (make-schema :models (list (make-model "blog" :list (list (make-field :title :text)
                                                                                         (make-field :cover :media)
                                                                                         (make-field :body :richtext))))))
      (ok (= (media-references "website" (media-id media)) 1) "and counts again once the field is back"))
    (testing "remove"
      (ok (= 409 (handler-case (progn (remove-media media) nil) (api-error (e) (api-error-status e))))
          "a file in use stays")
      (ok (find-media "website" (media-id media)))
      (koya-server/db/connection:exec "DELETE FROM contents")
      (remove-media media)
      (ok (null (find-media "website" (media-id media))))
      (ok (null (probe-file (media-path media))) "file gone"))))

(deftest rejected-uploads
  (flet ((status (thunk) (handler-case (progn (funcall thunk) nil) (api-error (e) (api-error-status e)))))
    (ok (= 422 (status (lambda () (store-upload "website" (bytes 1 2 3) :filename "x.bin")))) "unknown type")
    (ok (= 422 (status (lambda () (store-upload "website" (bytes) :filename "x.png")))) "empty")
    (ok (= 413 (status (lambda () (store-upload "website" (make-array (1+ koya-server/features/media/store:+max-upload-bytes+)
                                                                       :element-type '(unsigned-byte 8) :initial-element 0)
                                                :filename "big.png"))))
        "too large")))

(deftest deleting-a-space-takes-its-files
  ;; the rows go with the space through the foreign key; the files are the admin
  ;; UI's job afterwards, and nothing else ever deletes a whole library
  (create-space "doomed")
  (let* ((kept (store-upload "website" (png-bytes) :filename "kept.png"))
         (doomed (store-upload "doomed" (png-bytes) :filename "doomed.png"))
         (directory (uiop:pathname-directory-pathname (media-path doomed))))
    (ok (probe-file (media-path doomed)))
    (delete-space "doomed")
    (ok (null (find-media "doomed" (media-id doomed))) "the row went with the space")
    (ok (probe-file (media-path doomed)) "but not yet the file")
    (remove-space-media "doomed")
    (ok (null (probe-file (media-path doomed))) "file gone")
    (ng (uiop:directory-exists-p directory) "and the space's directory with it")
    (ok (probe-file (media-path kept)) "another space's files are untouched")
    (remove-media kept))
  (testing "a space that never had a file is not an error"
    (create-space "empty")
    (delete-space "empty")
    (ok (null (remove-space-media "empty")))))
