(defpackage #:koya-spec/server/usecases/media
  (:use #:cl #:rove)
  (:import-from #:koya-server/usecases/schema #:replace-schema)
  (:import-from #:koya-server/infra/db/connection #:connect-db #:disconnect-db #:exec)
  (:import-from #:koya-server/infra/db/migrations #:migrate)
  (:import-from #:koya-server/usecases/ports/spaces #:delete-space #:find-model)
  (:import-from #:koya-server/usecases/spaces #:create-space #:remove-space #:find-space)
  (:import-from #:koya-server/usecases/contents #:create)
  (:import-from #:koya-server/domain/content #:content-id)
  (:import-from #:koya-server/usecases/ports/media
                #:find-media #:list-media #:count-media #:update-media #:media-file-path
                #:insert-media #:delete-media-file)
  (:import-from #:koya-server/domain/image #:sniff-image)
  (:import-from #:koya-spec/server/domain/image #:jpeg #:octets)
  (:import-from #:koya-server/web/lib/presenters #:media-url #:media->jobject)
  (:import-from #:koya-server/usecases/media
                #:store-upload #:store-uploads #:remove-media #:remove-each #:remove-space-media #:media-references
                #:media-reference-counts)
  (:import-from #:koya-server/domain/media
                #:media-id #:media-space #:media-filename #:media-mime #:media-size #:media-width
                #:media-height #:media-alt #:+max-upload-bytes+)
  (:import-from #:koya-server/domain/errors
                #:koya-error #:koya-error-code #:conflict #:rejected #:too-large)
  (:import-from #:koya-core/schema #:make-field #:make-model #:make-schema)
  (:import-from #:koya-core/json #:jget #:parse-json)
  (:import-from #:babel #:string-to-octets)
  (:export #:png-bytes #:*media-root* #:multipart-body))
(in-package #:koya-spec/server/usecases/media)

(defvar *media-root*
  (uiop:ensure-directory-pathname
   (format nil "~a/koya-test-media-~a/" (or (uiop:getenv "TMPDIR") "/tmp") (get-universal-time))))

(defun media-path (media)
  (media-file-path (media-space media) (media-id media) (media-mime media)))

(defun bytes (&rest list) (coerce list '(vector (unsigned-byte 8))))

(defun png-bytes (&optional (width 3) (height 2))
  (flet ((be32 (n) (list (ldb (byte 8 24) n) (ldb (byte 8 16) n) (ldb (byte 8 8) n) (ldb (byte 8 0) n))))
    (apply #'bytes (append '(#x89 #x50 #x4E #x47 #x0D #x0A #x1A #x0A) (be32 13) '(#x49 #x48 #x44 #x52)
                           (be32 width) (be32 height) '(8 6 0 0 0)))))

(defun multipart-body (parts)
  (let ((boundary "----koyatest")
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
  (replace-schema "website"
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
      (sniff-image (bytes #xFF #xD8 #xFF #xC0 #x00 #x11 #x08 #x01 #x00 #x00 #x80 #x03 0 0 0 0 0 0 0 0))
    (ok (string= mime "image/jpeg")) (ok (= w 128)) (ok (= h 256)))
  (multiple-value-bind (mime w h)
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
      (ok (= (length (media-references "website" (media-id media))) 0))
      (let ((x (create "website" (find-model "website" "blog") (parse-json (format nil "{\"title\": \"x\", \"cover\": \"~a\"}" (media-id media)))))
            (y (create "website" (find-model "website" "blog") (parse-json (format nil "{\"title\": \"y\", \"body\": \"<img src=\\\"~a\\\">\"}" (media-url media))))))
        (ok (= (length (media-references "website" (media-id media))) 2) "field values and richtext URLs both count")
        (ok (equal (sort (mapcar (lambda (r) (getf r :label)) (media-references "website" (media-id media))) #'string<)
                   (sort (list (content-id x) (content-id y)) #'string<))
            "each one named, by its id when its model has no label"))
      (ok (= (gethash (media-id media) (media-reference-counts "website" (list (media-id media)))) 2)
          "the library's counts agree"))
    (testing "only the fields in the schema count"
      (exec "DELETE FROM contents")
      (create "website" (find-model "website" "blog") (parse-json (format nil "{\"title\": \"~a\"}" (media-id media))))
      (ok (= (length (media-references "website" (media-id media))) 0) "a text field mentioning the id is not a use")
      (create "website" (find-model "website" "blog") (parse-json (format nil "{\"title\": \"z\", \"cover\": \"~a\"}" (media-id media))))
      (ok (= (length (media-references "website" (media-id media))) 1))
      (replace-schema "website" (make-schema :models (list (make-model "blog" :list (list (make-field :title :text)
                                                                                         (make-field :body :richtext))))))
      (ok (= (length (media-references "website" (media-id media))) 0) "a field removed by a deploy takes its value with it")
      (ok (= (gethash (media-id media) (media-reference-counts "website" (list (media-id media)))) 0))
      (replace-schema "website" (make-schema :models (list (make-model "blog" :list (list (make-field :title :text)
                                                                                         (make-field :cover :media)
                                                                                         (make-field :body :richtext))))))
      (ok (= (length (media-references "website" (media-id media))) 0) "and the field back is empty"))
    (testing "remove"
      (create "website" (find-model "website" "blog") (parse-json (format nil "{\"title\": \"z\", \"cover\": \"~a\"}" (media-id media))))
      (ok (equal "in_use" (handler-case (progn (remove-media media) nil) (conflict (e) (koya-error-code e))))
          "a file in use stays")
      (ok (find-media "website" (media-id media)))
      (exec "DELETE FROM contents")
      (remove-media media)
      (ok (null (find-media "website" (media-id media))))
      (ok (null (probe-file (media-path media))) "file gone"))))

(deftest an-upload-is-stored-without-its-metadata
  (let* ((media (store-upload "website" (jpeg) :filename "phone.jpg"))
         (stored (alexandria:read-file-into-byte-vector (media-path media))))
    (ng (search (octets "GPS") stored) "where it was taken is not kept")
    (ok (= (media-size media) (length stored)) "its size is what is kept")
    (ok (< (length stored) (length (jpeg))))
    (remove-media media)))

(deftest rejected-uploads
  (flet ((refusal (thunk) (handler-case (progn (funcall thunk) nil) (koya-error (e) (type-of e)))))
    (ok (eq 'rejected (refusal (lambda () (store-upload "website" (bytes 1 2 3) :filename "x.bin")))) "unknown type")
    (ok (eq 'rejected (refusal (lambda () (store-upload "website" (bytes) :filename "x.png")))) "empty")
    (ok (eq 'too-large (refusal (lambda () (store-upload "website" (make-array (1+ +max-upload-bytes+)
                                                                       :element-type '(unsigned-byte 8) :initial-element 0)
                                                :filename "big.png"))))
        "too large")
    (ok (eq 'too-large (refusal (lambda () (store-uploads "website"
                                                          (loop :repeat 2
                                                                :collect (list (make-array (1+ (floor +max-upload-bytes+ 2))
                                                                                           :element-type '(unsigned-byte 8) :initial-element 0)
                                                                               "half.png"))))))
        "files each under the limit, but not together")))

(deftest deleting-a-space-takes-its-files

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

(deftest a-failed-write-leaves-no-row
  (let ((before (count-media "website"))
        (blocker (merge-pathnames "blocker" *media-root*)))
    (ensure-directories-exist blocker)
    (with-open-file (out blocker :direction :output :if-exists :supersede) (write-string "x" out))
    (setf (uiop:getenv "KOYA_MEDIA_DIR") (namestring (merge-pathnames "blocker/" *media-root*)))
    (unwind-protect
         (ok (handler-case (progn (store-upload "website" (png-bytes) :filename "lost.png") nil)
               (error () t))
             "the write fails")
      (setf (uiop:getenv "KOYA_MEDIA_DIR") (namestring *media-root*))
      (delete-file blocker))
    (ok (= (count-media "website") before) "and no row names the file it could not write")))

(deftest a-failed-insert-is-the-error-told
  (let* ((left nil)
         (insert (defmethod insert-media :around (space &key &allow-other-keys)
                   (declare (ignore space))
                   (error "The row is not written")))
         (cleanup (defmethod delete-media-file :around (space id mime)
                    (setf left (list space id mime))
                    (error "The file will not go"))))
    (unwind-protect
         (ok (equal (handler-case (progn (store-upload "website" (png-bytes) :filename "lost.png") nil)
                      (error (e) (princ-to-string e)))
                    "The row is not written")
             "the insert's error, not the one taking its file away")
      (remove-method #'insert-media insert)
      (remove-method #'delete-media-file cleanup)
      (when left (apply #'delete-media-file left)))))

(deftest removing-each-goes-past-a-file-that-will-not-go
  (let* ((stuck (store-upload "website" (png-bytes) :filename "stuck.png"))
         (free (store-upload "website" (png-bytes) :filename "free.png"))
         (path (media-path stuck)))
    (delete-file path)
    (ensure-directories-exist (merge-pathnames "inside/" (uiop:ensure-directory-pathname path)))
    (unwind-protect
         (multiple-value-bind (done failed message)
             (remove-each "website" (list (media-id stuck) (media-id free)))
           (ok (= failed 1))
           (ok (= done 1) "the one after it still goes")
           (ok (stringp message))
           (ok (null (find-media "website" (media-id free)))))
      (uiop:delete-directory-tree (uiop:ensure-directory-pathname path) :validate t))))

(deftest removing-a-space-takes-its-rows-and-files
  (create-space "gone")
  (let ((media (store-upload "gone" (png-bytes) :filename "gone.png")))
    (remove-space "gone")
    (ok (null (find-space "gone")))
    (ok (null (find-media "gone" (media-id media))))
    (ok (null (probe-file (media-path media))))))

(deftest a-media-among-several-is-in-use
  (replace-schema "website" (make-schema :models (list (make-model "blog" :list (list (make-field :title :text)
                                                                                     (make-field :photos :media :many t))))))
  (unwind-protect
       (let ((a (store-upload "website" (png-bytes) :filename "a.png"))
             (b (store-upload "website" (png-bytes) :filename "b.png")))
         (create "website" (find-model "website" "blog") (parse-json (format nil "{\"title\": \"x\", \"photos\": [\"~a\", \"~a\"]}" (media-id a) (media-id b))))
         (ok (= (length (media-references "website" (media-id b))) 1) "each one of them is a use")
         (ok (= (gethash (media-id a) (media-reference-counts "website" (list (media-id a)))) 1) "and the library counts it")
         (ok (equal "in_use" (handler-case (progn (remove-media b) nil) (conflict (e) (koya-error-code e))))))
    (exec "DELETE FROM contents")
    (replace-schema "website"
                    (make-schema :models (list (make-model "blog" :list (list (make-field :title :text)
                                                                              (make-field :cover :media)
                                                                              (make-field :body :richtext))))))))
