(defpackage #:koya-tests/server/usecases/contents/revisions
  (:use #:cl #:rove)
  (:import-from #:koya-server/infra/db/connection #:connect-db #:disconnect-db #:exec)
  (:import-from #:koya-server/infra/db/migrations #:migrate)
  (:import-from #:koya-server/usecases/schema/deploy #:replace-schema)
  (:import-from #:koya-server/usecases/spaces/lifecycle #:create-space #:find-model)
  (:import-from #:koya-server/usecases/contents/write #:create)
  (:import-from #:koya-server/usecases/contents/revisions #:restore-data)
  (:import-from #:koya-server/usecases/ports/media #:insert-media)
  (:import-from #:koya-server/domain/media #:media-id)
  (:import-from #:koya-server/domain/content #:content-id)
  (:import-from #:koya/core/schema #:make-field #:make-model #:make-schema)
  (:import-from #:koya/core/json #:jget))
(in-package #:koya-tests/server/usecases/contents/revisions)

;;; What an old version becomes when it is brought back into the editor. The
;;; schema and the space may have moved on: a field gone, a rule tightened, a
;;; reference or a media no longer there. Each is a note, never a guess.

(defun schema (&rest post-fields)
  (make-schema :models (list (make-model "post" :list post-fields)
                             (make-model "tag" :list (list (make-field :name :text))))))

(setup
  (connect-db ":memory:")
  (migrate)
  (create-space "site"))

(teardown (disconnect-db))

(defhook :before
  (exec "DELETE FROM contents")
  (exec "DELETE FROM media")
  (replace-schema "site" (schema (make-field :title :text :required t)
                                 (make-field :lede :text)
                                 (make-field :count :number :max 10)
                                 (make-field :slug :slug :from :title :unique t)
                                 (make-field :cover :media)
                                 (make-field :tags :reference :model "tag" :many t))))

(defun object (&rest plist)
  (let ((table (make-hash-table :test 'equal)))
    (loop :for (k v) :on plist :by #'cddr :do (setf (gethash k table) v))
    table))
(defun post () (find-model "site" "post"))
(defun notes-of (notes) (mapcar (lambda (n) (getf n :field)) notes))

(deftest a-version-comes-back-as-it-was
  (multiple-value-bind (data notes)
      (restore-data "site" (post) "x" (object "title" "Old" "lede" "Then" "count" 3) (object "title" "Now"))
    (ok (null notes))
    (ok (string= (jget data "title") "Old"))
    (ok (string= (jget data "lede") "Then"))
    (ok (= (jget data "count") 3))))

(deftest what-the-schema-no-longer-has
  (testing "a field that is gone is left out, and said"
    (replace-schema "site" (schema (make-field :title :text :required t)))
    (multiple-value-bind (data notes) (restore-data "site" (post) "x" (object "title" "Old" "lede" "Then") (object))
      (ok (string= (jget data "title") "Old"))
      (ng (nth-value 1 (gethash "lede" data)))
      (ok (equal (notes-of notes) '("lede")))))
  (testing "a value the field no longer accepts keeps the current one"
    (replace-schema "site" (schema (make-field :title :text :required t) (make-field :count :number :max 10)))
    (multiple-value-bind (data notes) (restore-data "site" (post) "x" (object "title" "Old" "count" 99) (object "count" 5))
      (ok (= (jget data "count") 5))
      (ok (equal (notes-of notes) '("count")))
      (ok (search "no longer accepts" (getf (first notes) :note)))))
  (testing "a field that is required now, and was empty then, keeps the current value"
    (replace-schema "site" (schema (make-field :title :text :required t) (make-field :lede :text :required t)))
    (multiple-value-bind (data notes) (restore-data "site" (post) "x" (object "title" "Old") (object "lede" "Kept"))
      (ok (string= (jget data "lede") "Kept"))
      (ok (equal (notes-of notes) '("lede"))))))

(deftest what-the-space-no-longer-has
  (let* ((live (create "site" (find-model "site" "tag") (object "name" "live") :publish t))
         (drafted (create "site" (find-model "site" "tag") (object "name" "draft")))
         (media (insert-media "site" :filename "c.png" :mime "image/png" :size 1)))
    (testing "references to what is gone or unpublished are dropped, the rest kept"
      (multiple-value-bind (data notes)
          (restore-data "site" (post) "x"
                        (object "title" "Old" "tags" (vector (content-id live) (content-id drafted) "gone"))
                        (object))
        (ok (equalp (jget data "tags") (vector (content-id live))))
        (ok (equal (notes-of notes) '("tags")))
        (ok (search "2 references" (getf (first notes) :note)))))
    (testing "a media that is still in the library comes back; one that is not is dropped"
      (ok (string= (jget (restore-data "site" (post) "x" (object "title" "Old" "cover" (media-id media)) (object)) "cover")
                   (media-id media)))
      (multiple-value-bind (data notes) (restore-data "site" (post) "x" (object "title" "Old" "cover" "01GONE") (object))
        (ng (nth-value 1 (gethash "cover" data)))
        (ok (equal (notes-of notes) '("cover")))))))

(deftest a-unique-value-another-content-took-since
  (let ((other (create "site" (post) (object "title" "Taken" "slug" "taken") :publish t))
        (mine (create "site" (post) (object "title" "Mine" "slug" "mine") :publish t)))
    (multiple-value-bind (data notes)
        (restore-data "site" (post) (content-id mine) (object "title" "Mine" "slug" "taken") (object "slug" "mine"))
      (ok (string= (jget data "slug") "mine") "the version's slug is the other content's now")
      (ok (equal (notes-of notes) '("slug"))))
    (ok (string= (jget (restore-data "site" (post) (content-id other) (object "title" "Taken" "slug" "taken") (object)) "slug")
                 "taken")
        "a content's own value is not taken from it")))
