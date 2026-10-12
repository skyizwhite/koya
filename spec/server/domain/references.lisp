(defpackage #:koya-spec/server/domain/references
  (:use #:cl #:rove)
  (:import-from #:koya-core/schema #:make-field #:make-model #:make-schema)
  (:import-from #:koya-server/domain/content #:make-content #:status-of)
  (:import-from #:koya-server/domain/references
                #:reference-fields #:refers-p #:media-fields #:mentioned-ids))
(in-package #:koya-spec/server/domain/references)

(defun schema ()
  (make-schema :models (list (make-model "post" :list (list (make-field :title :text)
                                                            (make-field :author :reference :model "person")
                                                            (make-field :tags :reference :model "tag" :many t)
                                                            (make-field :cover :media)
                                                            (make-field :body :richtext)))
                             (make-model "person" :list (list (make-field :name :text))))))

(defun post (&key published draft)
  (make-content :id "p1" :model "post"
                :status (status-of published draft)
                :published published :draft draft))

(deftest references
  (let ((to-tags (reference-fields (schema) "tag")))
    (ok (equal (alexandria:hash-table-keys to-tags) '("post")) "only the models with a field pointing there")
    (ok (refers-p (post :published (list :tags #("t1" "t2"))) to-tags "t2") "one of many")
    (ok (refers-p (post :published (list :tags #("x")) :draft (list :tags #("t1"))) to-tags "t1") "the draft counts")
    (ng (refers-p (post :published (list :title "t1")) to-tags "t1") "a text field holding the id is not a reference")
    (ng (refers-p (post :published (list :author "t1")) to-tags "t1") "nor a reference to another model")
    (ng (refers-p (post :published (list :tags #("t1"))) (reference-fields (make-schema) "tag") "t1")
        "a field the schema no longer has is not read")))

(deftest mentions
  (let ((fields (media-fields (schema))))
    (ok (equal (mentioned-ids (post :published (list :cover "m1")) fields '("m1" "m2")) '("m1")) "a media field by id")
    (ok (equal (mentioned-ids (post :draft (list :body "<img src=\"/media/s/m2.png\">")) fields '("m1" "m2")) '("m2"))
        "a richtext field by URL")
    (ok (null (mentioned-ids (post :published (list :title "m1")) fields '("m1"))) "a text field is not a use")
    (ok (= 1 (length (mentioned-ids (post :published (list :cover "m1") :draft (list :cover "m1")) fields '("m1"))))
        "published and draft together mention it once")
    (ok (null (mentioned-ids (make-content :id "p1" :model "post" :status "draft" :published (list :cover "m1"))
                             fields '("m1")))
        "a version the status does not have is not read")))
