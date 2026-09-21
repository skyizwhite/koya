(defpackage #:koya-tests/core/schema
  (:use #:cl #:rove)
  (:import-from #:koya/core/schema
                #:make-field #:make-model #:make-schema
                #:field-name #:field-type #:field-option
                #:model-field #:model-kind #:schema-model #:schema-webhooks
                #:model-preview-url #:model-public-url #:make-webhook #:webhook-only #:webhook-covers-p
                #:schema-error #:schema-errors #:check-schema
                #:schema->jobject #:jobject->schema)
  (:import-from #:koya/core/json
                #:to-json #:parse-json #:jget))
(in-package #:koya-tests/core/schema)

(defun sample-schema ()
  (make-schema
   :webhooks (list (make-webhook "hook" "https://example.com/hook")
                   (make-webhook "blog-only" "https://example.com/blog-hook" :only '(blog)))
   :models (list (make-model "blog" :list
                             (list (make-field :title :text :required t :max-length 100)
                                   (make-field :slug :slug :from :title :unique t)
                                   (make-field :content :richtext)
                                   (make-field :tags :reference :model "tag" :many t)
                                   (make-field :event-at :datetime)))
                 (make-model "tag" :list (list (make-field :name :text :required t)))
                 (make-model "about" :object (list (make-field :body :richtext))
                             :preview-url "https://x/about?draft-key={DRAFT_KEY}"
                             :public-url "https://x/about"))))

(deftest constructors
  (testing "field names are camelCased"
    (ok (string= (field-name (make-field :event-at :datetime)) "eventAt")))
  (testing "rejects unknown types and options"
    (ok (signals (make-field :x :nope) 'schema-error))
    (ok (signals (make-field :x :text :min 3) 'schema-error))
    (ok (signals (make-field :x :select) 'schema-error) "select needs options")
    (ok (signals (make-field :x :reference) 'schema-error) "reference needs model")
    (ok (signals (make-field :x :slug) 'schema-error) "slug needs from")
    (ok (signals (make-field "Bad Name" :text) 'schema-error))
    (ok (signals (make-field (format nil "title~%") :text) 'schema-error) "no trailing newline")
    (ok (signals (make-field :x :text :pattern "(") 'schema-error) "broken regex")
    (ok (signals (make-field :x :text :pattern 5) 'schema-error) "pattern must be a string")
    (ok (signals (make-field :x :text :max-length "ten") 'schema-error))
    (ok (signals (make-field :x :text :required "yes") 'schema-error))
    (ok (signals (make-field :x :select :options "abc") 'schema-error) "options must be a list")
    (ok (signals (make-field :x :select :options '("a" "a")) 'schema-error) "no duplicate options")
    (ok (equal (field-option (make-field :x :select :options '(news tech)) :options) '("news" "tech"))
        "symbol options are downcased like model names")
    (ok (signals (make-schema :webhooks "https://x") 'schema-error) "webhooks must be a list")
    (ok (signals (make-webhook "" "https://x") 'schema-error) "label needed")
    (ok (signals (make-webhook "x" "") 'schema-error) "url needed")
    (ok (signals (make-schema :webhooks '("https://x")) 'schema-error) "a bare URL is not a webhook")
    (ok (signals (make-schema :webhooks (list (make-webhook "a" "https://x") (make-webhook "a" "https://y"))) 'schema-error)
        "labels are unique within a space")
    (let ((wire (jobject->schema (parse-json "{\"koyaSchema\": 1, \"webhooks\": [{\"label\": \"new\", \"url\": \"https://new\", \"events\": [\"draft\"]}, {\"url\": \"https://m\", \"only\": [\"m\"]}], \"models\": [{\"name\": \"m\", \"kind\": \"list\", \"webhooks\": [{\"url\": \"https://old\"}]}]}"))))
      (ok (equal (first (schema-webhooks wire)) '(:label "new" :url "https://new"))
          "the events older schemas carried are dropped on load")
      (ok (equal (second (schema-webhooks wire)) '(:label "https://m" :url "https://m" :only ("m")))
          "a label defaults to the URL on the wire, and :only survives it")
      (ok (null (koya/core/schema:model-options (schema-model wire "m")))
          "a webhooks key left on a model by an older schema is ignored"))
    (testing ":only"
      (ok (null (webhook-only (make-webhook "a" "https://a"))) "absent means every model")
      (ok (equal (webhook-only (make-webhook "a" "https://a" :only 'blog)) '("blog")) "one name is a list of one")
      (ok (equal (webhook-only (make-webhook "a" "https://a" :only '(blog about))) '("blog" "about")))
      (ok (webhook-covers-p (make-webhook "a" "https://a") "anything"))
      (ok (webhook-covers-p (make-webhook "a" "https://a" :only '(blog about)) "about"))
      (ng (webhook-covers-p (make-webhook "a" "https://a" :only '(blog)) "about"))
      (ok (signals (make-webhook "a" "https://a" :only "Not A Slug") 'schema-error))
      (ok (signals (make-webhook "a" "https://a" :only 5) 'schema-error))
      (ok (signals (make-webhook "a" "https://a" :only '(blog blog)) 'schema-error) "no duplicates"))
    (ok (signals (jobject->schema (parse-json "{\"koyaSchema\": 1, \"webhooks\": [\"https://old\"]}"))
                 'schema-error)
        "a bare URL is not a webhook on the wire either")
    (ok (signals (make-model (format nil "blog~%") :list nil) 'schema-error) "no trailing newline"))
  (testing "model names must be slugs"
    (ok (signals (make-model "Blog Post" :list nil) 'schema-error))
    (ok (signals (make-model "blog" :weird nil) 'schema-error)))
  (testing "duplicates"
    (ok (signals (make-model "m" :list (list (make-field :a :text) (make-field :a :text))) 'schema-error))
    (ok (signals (make-schema :models (list (make-model "m" :list nil) (make-model "m" :list nil))) 'schema-error))))

(deftest lookups
  (let* ((schema (sample-schema))
         (blog (schema-model schema :blog)))
    (ok blog)
    (ok (eq (model-kind blog) :list))
    (ok (eq (model-kind (schema-model schema "about")) :object))
    (ok (model-field blog :event-at))
    (ok (eq (field-type (model-field blog "eventAt")) :datetime))
    (ok (signals (make-field :published-at :datetime) 'schema-error) "system field names are reserved")
    (ng (model-field blog :nope))))

(deftest cross-references
  (ok (null (schema-errors (sample-schema))))
  (let ((broken (make-schema :models (list (make-model "m" :list (list (make-field :r :reference :model "ghost")))))))
    (ok (= (length (schema-errors broken)) 1))
    (ok (signals (check-schema broken) 'schema-error)))
  (let ((broken (make-schema :models (list (make-model "m" :list (list (make-field :s :slug :from :ghost)))))))
    (ok (= (length (schema-errors broken)) 1)))
  (testing ":only must name models of this schema"
    (let ((broken (make-schema :webhooks (list (make-webhook "h" "https://h" :only '(ghost)))
                               :models (list (make-model "m" :list nil)))))
      (ok (= (length (schema-errors broken)) 1))
      (ok (signals (check-schema broken) 'schema-error)))
    (ok (null (schema-errors (make-schema :webhooks (list (make-webhook "h" "https://h" :only '(m)))
                                          :models (list (make-model "m" :list nil))))))))

(deftest wire-format
  (let* ((schema (sample-schema))
         (obj (schema->jobject schema))
         (json (to-json obj))
         (back (jobject->schema (parse-json json))))
    (ok (= (jget obj "koyaSchema") 1))
    (ok (search "\"maxLength\":100" json))
    (ok (search "\"eventAt\"" json))
    (ok (search "\"kind\":\"object\"" json))
    (ok (equal (schema-webhooks back)
               '((:label "hook" :url "https://example.com/hook")
                 (:label "blog-only" :url "https://example.com/blog-hook" :only ("blog")))))
    (ok (search "\"webhooks\":[{\"label\":\"hook\"" json) "webhooks are objects on the wire")
    (ok (search "\"only\":[\"blog\"]" json))
    (let ((blog (schema-model back :blog)))
      (ok (= (field-option (model-field blog :title) :max-length) 100))
      (ok (field-option (model-field blog :tags) :many))
      (ok (string= (field-option (model-field blog :tags) :model) "tag"))
      (ok (string= (field-option (model-field blog :slug) :from) "title")))
    (let ((about (schema-model back :about)))
      (ok (string= (model-preview-url about) "https://x/about?draft-key={DRAFT_KEY}"))
      (ok (string= (model-public-url about) "https://x/about"))
      (ok (search "\"previewUrl\"" json)))
    (ok (null (model-public-url (schema-model back :blog))) "absent when not set")
    (testing "round trip is stable"
      (ok (string= json (to-json (schema->jobject back))))))
  (testing "rejects bad input"
    (ok (signals (jobject->schema (parse-json "{\"koyaSchema\": 2}")) 'schema-error))
    (ok (signals (jobject->schema (parse-json "{\"koyaSchema\": 1, \"models\": [{\"name\": \"m\", \"kind\": \"list\", \"fields\": [{\"name\": \"f\", \"type\": \"nope\"}]}]}")) 'schema-error))
    (ok (signals (jobject->schema (parse-json "[]")) 'schema-error))
    (dolist (json '("{\"koyaSchema\": 1, \"models\": 5}"
                    "{\"koyaSchema\": 1, \"webhooks\": \"https://x\"}"
                    "{\"koyaSchema\": 1, \"models\": [{\"name\": \"m\", \"kind\": \"list\", \"fields\": 5}]}"
                    "{\"koyaSchema\": 1, \"models\": [{\"name\": \"m\", \"kind\": \"LIST\"}]}"
                    "{\"koyaSchema\": 1, \"models\": [{\"name\": \"m\", \"kind\": \"list\", \"fields\": [{\"name\": \"f\", \"type\": \"text\", \"pattern\": \"(\"}]}]}"
                    "{\"koyaSchema\": 1, \"models\": [{\"name\": \"m\", \"kind\": \"list\", \"fields\": [{\"name\": \"f\", \"type\": \"text\", \"bogus\": 1}]}]}"
                    "{\"koyaSchema\": 1, \"models\": [{\"name\": \"m\", \"kind\": \"list\", \"fields\": [{\"name\": \"f\", \"type\": \"select\", \"options\": \"abc\"}]}]}"))
      (ok (signals (jobject->schema (parse-json json)) 'schema-error) json))))
