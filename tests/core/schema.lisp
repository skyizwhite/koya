(defpackage #:koya-tests/core/schema
  (:use #:cl #:rove)
  (:import-from #:koya/core/schema
                #:make-field #:make-model #:make-space #:make-schema
                #:field-name #:field-type #:field-option
                #:model-field #:model-kind #:space-model #:schema-space #:space-webhooks
                #:schema-error #:schema-errors #:check-schema
                #:schema->jobject #:jobject->schema)
  (:import-from #:koya/core/json
                #:to-json #:parse-json #:jget))
(in-package #:koya-tests/core/schema)

(defun sample-schema ()
  (make-schema
   (list (make-space "website"
                     :webhooks '("https://example.com/hook")
                     :models (list (make-model "blog" :list
                                               (list (make-field :title :text :required t :max-length 100)
                                                     (make-field :slug :slug :from :title :unique t)
                                                     (make-field :content :richtext)
                                                     (make-field :tags :reference :model "tag" :many t)
                                                     (make-field :event-at :datetime)))
                                   (make-model "tag" :list (list (make-field :name :text :required t)))
                                   (make-model "about" :object (list (make-field :body :richtext))))))))

(deftest constructors
  (testing "field names are camelCased"
    (ok (string= (field-name (make-field :event-at :datetime)) "eventAt")))
  (testing "rejects unknown types and options"
    (ok (signals (make-field :x :nope) 'schema-error))
    (ok (signals (make-field :x :text :min 3) 'schema-error))
    (ok (signals (make-field :x :select) 'schema-error) "select needs options")
    (ok (signals (make-field :x :reference) 'schema-error) "reference needs model")
    (ok (signals (make-field :x :slug) 'schema-error) "slug needs from")
    (ok (signals (make-field "Bad Name" :text) 'schema-error)))
  (testing "model and space names must be slugs"
    (ok (signals (make-model "Blog Post" :list nil) 'schema-error))
    (ok (signals (make-model "blog" :weird nil) 'schema-error))
    (ok (signals (make-space "My Space") 'schema-error)))
  (testing "duplicates"
    (ok (signals (make-model "m" :list (list (make-field :a :text) (make-field :a :text))) 'schema-error))
    (ok (signals (make-schema (list (make-space "a") (make-space "a"))) 'schema-error))))

(deftest lookups
  (let* ((schema (sample-schema))
         (space (schema-space schema :website))
         (blog (space-model space :blog)))
    (ok space)
    (ok (eq (model-kind blog) :list))
    (ok (eq (model-kind (space-model space "about")) :object))
    (ok (model-field blog :event-at))
    (ok (eq (field-type (model-field blog "eventAt")) :datetime))
    (ok (signals (make-field :published-at :datetime) 'schema-error) "system field names are reserved")
    (ng (model-field blog :nope))))

(deftest cross-references
  (ok (null (schema-errors (sample-schema))))
  (let ((broken (make-schema (list (make-space "s" :models (list (make-model "m" :list (list (make-field :r :reference :model "ghost")))))))))
    (ok (= (length (schema-errors broken)) 1))
    (ok (signals (check-schema broken) 'schema-error)))
  (let ((broken (make-schema (list (make-space "s" :models (list (make-model "m" :list (list (make-field :s :slug :from :ghost)))))))))
    (ok (= (length (schema-errors broken)) 1))))

(deftest wire-format
  (let* ((schema (sample-schema))
         (obj (schema->jobject schema))
         (json (to-json obj))
         (back (jobject->schema (parse-json json))))
    (ok (= (jget obj "koyaSchema") 1))
    (ok (search "\"maxLength\":100" json))
    (ok (search "\"eventAt\"" json))
    (ok (search "\"kind\":\"object\"" json))
    (ok (equal (space-webhooks (schema-space back :website)) '("https://example.com/hook")))
    (let ((blog (space-model (schema-space back :website) :blog)))
      (ok (= (field-option (model-field blog :title) :max-length) 100))
      (ok (field-option (model-field blog :tags) :many))
      (ok (string= (field-option (model-field blog :tags) :model) "tag"))
      (ok (string= (field-option (model-field blog :slug) :from) "title")))
    (testing "round trip is stable"
      (ok (string= json (to-json (schema->jobject back))))))
  (testing "rejects bad input"
    (ok (signals (jobject->schema (parse-json "{\"koyaSchema\": 2, \"spaces\": []}")) 'schema-error))
    (ok (signals (jobject->schema (parse-json "{\"koyaSchema\": 1, \"spaces\": [{\"name\": \"s\", \"models\": [{\"name\": \"m\", \"kind\": \"list\", \"fields\": [{\"name\": \"f\", \"type\": \"nope\"}]}]}]}")) 'schema-error))
    (ok (signals (jobject->schema (parse-json "[]")) 'schema-error))))
