(defpackage #:koya-tests/server/usecases/contents/delivery
  (:use #:cl #:rove)
  (:import-from #:koya-server/infra/db/connection #:connect-db #:disconnect-db #:exec)
  (:import-from #:koya-server/infra/db/migrations #:migrate)
  (:import-from #:koya-server/usecases/schema/deploy #:replace-schema)
  (:import-from #:koya-server/usecases/spaces/lifecycle #:create-space #:find-model)
  (:import-from #:koya-server/usecases/contents/write #:create #:update-draft #:draft-key)
  (:import-from #:koya-server/usecases/contents/delivery
                #:deliver #:delivered-data #:delivered-p #:delivered-content
                #:delivered-one #:delivered-list #:delivered-object)
  (:import-from #:koya-server/usecases/ports/media #:insert-media)
  (:import-from #:koya-server/domain/media #:media-p #:media-id)
  (:import-from #:koya-server/domain/content #:content-id)
  (:import-from #:koya-server/domain/errors #:not-found #:koya-error-code)
  (:import-from #:koya-server/domain/query #:parse-query #:make-query #:query-error)
  (:import-from #:koya/core/schema #:make-field #:make-model #:make-schema)
  (:import-from #:koya/core/json #:jobject #:jget #:json-null #:json-null-p))
(in-package #:koya-tests/server/usecases/contents/delivery)

;;; What the delivery API hands the presenter: a content's data with its media
;;; and the references it was asked for, resolved. No HTTP, no JSON.

(setup
  (connect-db ":memory:")
  (migrate)
  (create-space "site")
  (replace-schema "site"
                  (make-schema :models (list (make-model "post" :list (list (make-field :title :text :required t)
                                                                           (make-field :cover :media)
                                                                           (make-field :author :reference :model "author")
                                                                           (make-field :tags :reference :model "tag" :many t)))
                                             (make-model "author" :list (list (make-field :name :text)
                                                                             (make-field :avatar :media)
                                                                             (make-field :favorite :reference :model "tag")))
                                             (make-model "tag" :list (list (make-field :name :text)))
                                             (make-model "about" :object (list (make-field "body" :text)))))))

(teardown (disconnect-db))

(defhook :before (exec "DELETE FROM contents") (exec "DELETE FROM media"))

(defun model (name) (find-model "site" name))
(defun make (model-name data &rest args)
  (apply #'create "site" (model model-name) (jobject-from data) args))
(defun jobject-from (plist)
  (let ((object (make-hash-table :test 'equal)))
    (loop :for (k v) :on plist :by #'cddr :do (setf (gethash k object) v))
    object))
(defun query (&rest kv) (parse-query (loop :for (k v) :on kv :by #'cddr :collect (cons k v))))
(defun picture (id)
  (media-id (insert-media "site" :id id :filename "p.png" :mime "image/png" :size 1 :width 1 :height 1)))

(deftest media-fields-hold-their-media
  (let* ((cover (picture "01ARZ3NDEKTSV4RRFFQ69G5FAA"))
         (post (make "post" (list "title" "One" "cover" cover) :publish t))
         (data (delivered-data (deliver post (model "post") "site"))))
    (ok (media-p (jget data "cover")) "the id became the media, without being asked")
    (ok (string= (media-id (jget data "cover")) cover))
    (testing "a media that has since gone is null, not a dangling id"
      (exec "DELETE FROM media")
      (ok (json-null-p (jget (delivered-data (deliver post (model "post") "site")) "cover"))))
    (testing "the content itself is untouched"
      (ok (stringp (jget (koya-server/domain/content:content-published post) "cover"))))))

(deftest references-stay-ids-unless-included
  (let* ((author (make "author" (list "name" "Ann") :publish t))
         (tag (make "tag" (list "name" "lisp") :publish t))
         (draft-tag (make "tag" (list "name" "unseen")))
         (post (make "post" (list "title" "One" "author" (content-id author)
                                  "tags" (vector (content-id tag) (content-id draft-tag) "gone"))
                     :publish t)))
    (let ((plain (delivered-data (deliver post (model "post") "site"))))
      (ok (string= (jget plain "author") (content-id author)) "an id, as stored")
      (ok (= (length (jget plain "tags")) 3)))
    (let ((data (delivered-data (deliver post (model "post") "site" :include '(("author") ("tags"))))))
      (ok (delivered-p (jget data "author")) "included: the content, delivered in turn")
      (ok (string= (jget (delivered-data (jget data "author")) "name") "Ann"))
      (ok (= (length (jget data "tags")) 1) "of three tags only the published one that exists is delivered")
      (ok (string= (jget (delivered-data (aref (jget data "tags") 0)) "name") "lisp")))
    (testing "what is included carries its media, and a path names its references"
      (let* ((avatar (picture "01ARZ3NDEKTSV4RRFFQ69G5FAB"))
             (pictured (make "author" (list "name" "Bo" "avatar" avatar "favorite" (content-id tag)) :publish t))
             (post (make "post" (list "title" "Two" "author" (content-id pictured)) :publish t))
             (shallow (delivered-data (jget (delivered-data (deliver post (model "post") "site" :include '(("author")))) "author")))
             (deep (delivered-data (jget (delivered-data (deliver post (model "post") "site" :include '(("author" "favorite")))) "author"))))
        (ok (media-p (jget shallow "avatar")) "media, always")
        (ok (stringp (jget shallow "favorite")) "a reference, only when its path is asked for")
        (ok (delivered-p (jget deep "favorite")))
        (ok (string= (jget (delivered-data (jget deep "favorite")) "name") "lisp"))))
    (testing "an include that names no reference field is a bad query"
      (ok (signals (deliver post (model "post") "site" :include '(("title"))) 'query-error)))))

(deftest what-is-delivered-and-what-is-not
  (let* ((live (make "post" (list "title" "Live") :publish t))
         (draft (make "post" (list "title" "Draft")))
         (id (content-id draft)))
    (ok (string= (jget (delivered-data (delivered-one "site" (model "post") (content-id live) (query))) "title") "Live"))
    (ok (signals (delivered-one "site" (model "post") id (query)) 'not-found) "a draft is not there")
    (ok (signals (delivered-one "site" (model "post") "nope" (query)) 'not-found))
    (testing "but its draft key opens it, as a preview"
      (let ((key (draft-key "site" "post" id)))
        (ok (string= (jget (delivered-data (delivered-one "site" (model "post") id (query) :draft-key key)) "title") "Draft"))
        (ok (signals (delivered-one "site" (model "post") id (query) :draft-key "wrong") 'not-found))
        (testing "and shows the draft of a published content, where the key is the new draft's"
          (update-draft "site" (model "post") (content-id live) (jobject-from (list "title" "Live, edited")))
          (let ((key (draft-key "site" "post" (content-id live))))
            (ok (string= (jget (delivered-data (delivered-one "site" (model "post") (content-id live) (query) :draft-key key)) "title")
                         "Live, edited"))
            (ok (string= (jget (delivered-data (delivered-one "site" (model "post") (content-id live) (query))) "title")
                         "Live") "without it, what is live")))))
    (testing "a list is the published ones, with how many there are"
      (multiple-value-bind (items total) (delivered-list "site" (model "post") (query "limit" "1"))
        (ok (= total 1))
        (ok (= (length items) 1))
        (ok (string= (content-id (delivered-content (first items))) (content-id live)))))
    (testing "an object model delivers its one content"
      (ok (signals (delivered-object "site" (model "about") (query)) 'not-found) "none yet")
      (make "about" (list "body" "hi") :publish t)
      (ok (string= (jget (delivered-data (delivered-object "site" (model "about") (query))) "body") "hi")))))
