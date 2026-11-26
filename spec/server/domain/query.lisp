(defpackage #:koya-spec/server/domain/query
  (:use #:cl #:rove)
  (:import-from #:koya-server/domain/query #:sortable-p)
  (:import-from #:koya-core/schema #:make-field #:make-model))
(in-package #:koya-spec/server/domain/query)

(defun model ()
  (make-model "post" :list (list (make-field :title :text)
                                 (make-field :slug :slug)
                                 (make-field :count :number)
                                 (make-field :featured :boolean)
                                 (make-field :day :date)
                                 (make-field :at :datetime)
                                 (make-field :summary :textarea)
                                 (make-field :body :richtext)
                                 (make-field :category :select :options '("news" "tech"))
                                 (make-field :labels :select :options '("a" "b") :many t)
                                 (make-field :cover :media)
                                 (make-field :gallery :media :many t)
                                 (make-field :author :reference :model "post")
                                 (make-field :related :reference :model "post" :many t)
                                 (make-field :meta :custom :custom-field "seo")
                                 (make-field :blocks :repeater :custom-fields '("seo")))))

(deftest a-list-sorts-by-a-field-whose-order-means-something
  (testing "a value read in order: text, slug, number, boolean, date and datetime"
    (dolist (name '("title" "slug" "count" "featured" "day" "at"))
      (ok (sortable-p (model) name) name)))
  (testing "and every system field"
    (dolist (name '("id" "createdAt" "updatedAt" "publishedAt" "revisedAt"))
      (ok (sortable-p (model) name) name)))
  (testing "not prose, a choice, an id of another record, or fields of its own"
    (dolist (name '("summary" "body" "category" "labels" "cover" "gallery" "author" "related" "meta" "blocks"))
      (ng (sortable-p (model) name) name)))
  (testing "nor a field the model does not have"
    (ng (sortable-p (model) "nope"))
    (ng (sortable-p (model) nil))))
