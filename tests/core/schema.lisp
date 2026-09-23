(defpackage #:koya-tests/core/schema
  (:use #:cl #:rove)
  (:import-from #:koya/core/schema
                #:make-field #:make-model #:make-schema
                #:field-name #:field-type #:field-option #:field-was
                #:model-field #:model-kind #:model-was #:model-forget-renames
                #:schema-model #:schema-webhooks
                #:model-preview-url #:model-public-url #:model-label #:make-webhook #:webhook-only #:webhook-covers-p
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

(deftest renames
  (testing ":was names what something used to be called"
    (ok (string= (field-was (make-field :subtitle :text :was :lede)) "lede") "camelCased like a field name")
    (ok (string= (model-was (make-model "article" :list nil :was 'post)) "post"))
    (ok (null (field-was (make-field :subtitle :text))))
    (ok (field-was (make-field :subtitle :media :was :picture)) ":was is allowed on every type"))
  (testing "a rename must name something other than itself"
    (ok (signals (make-field :title :text :was :title) 'schema-error))
    (ok (signals (make-model "blog" :list nil :was 'blog) 'schema-error))
    (ok (signals (make-field :title :text :was "Not A Field") 'schema-error))
    (ok (signals (make-field :title :text :was :created-at) 'schema-error) "system fields are not renamed")
    (ok (signals (make-model "blog" :list nil :was "Not A Model") 'schema-error))
    (ok (signals (jobject->schema (parse-json "{\"koyaSchema\": 1, \"models\": [{\"name\": \"m\", \"kind\": \"list\", \"was\": 5}]}"))
                 'schema-error)
        "a was that is not a name at all is refused, not left to signal elsewhere"))
  (testing "within a model a rename is unambiguous"
    (ok (signals (make-model "m" :list (list (make-field :a :text :was :old)
                                             (make-field :b :text :was :old)))
                 'schema-error)
        "two fields cannot come from the same one")
    (ok (signals (make-model "m" :list (list (make-field :old :text)
                                             (make-field :new :text :was :old)))
                 'schema-error)
        "a field cannot be renamed from one the model still declares"))
  (testing "the server stores the shape, not the instruction"
    (let ((stored (model-forget-renames
                   (make-model "article" :list (list (make-field :subtitle :text :required t :was :lede))
                               :was 'post :public-url "https://x"))))
      (ok (null (model-was stored)))
      (ok (null (field-was (model-field stored :subtitle))))
      (ok (field-option (model-field stored :subtitle) :required) "the rest of the field is untouched")
      (ok (string= (model-public-url stored) "https://x"))))
  (testing "an option given as nothing is not a rename"
    (ok (null (field-was (make-field :subtitle :text :was nil))))
    (ok (null (model-was (make-model "article" :list nil :was nil)))))
  (testing "a JSON null is not the name \"null\""
    (dolist (json '("{\"koyaSchema\": 1, \"models\": [{\"name\": \"m\", \"kind\": \"list\", \"was\": null}]}"
                    "{\"koyaSchema\": 1, \"models\": [{\"name\": \"m\", \"kind\": \"list\", \"fields\": [{\"name\": \"a\", \"type\": \"text\", \"was\": null}]}]}"))
      (ok (signals (jobject->schema (parse-json json)) 'schema-error) json)))
  (testing "a rename travels over the wire"
    (let* ((schema (make-schema :models (list (make-model "article" :list
                                                          (list (make-field :subtitle :text :was :lede))
                                                          :was 'post))))
           (json (to-json (schema->jobject schema)))
           (back (schema-model (jobject->schema (parse-json json)) "article")))
      (ok (search "\"was\":\"post\"" json))
      (ok (search "\"was\":\"lede\"" json))
      (ok (string= (model-was back) "post"))
      (ok (string= (field-was (model-field back :subtitle)) "lede")))))

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
  (testing "two models cannot be renamed from the same one"
    (let ((broken (make-schema :models (list (make-model "article" :list nil :was 'post)
                                             (make-model "news" :list nil :was 'post)))))
      (ok (= (length (schema-errors broken)) 1)
          "only one of them could have the contents, so neither is applied")
      (ok (signals (check-schema broken) 'schema-error))))
  (testing "a model cannot be renamed from one the schema still declares"
    (let ((broken (make-schema :models (list (make-model "post" :list nil)
                                             (make-model "article" :list nil :was 'post)))))
      (ok (= (length (schema-errors broken)) 1))
      (ok (signals (check-schema broken) 'schema-error)))
    (ok (null (schema-errors (make-schema :models (list (make-model "article" :list nil :was 'post)))))
        "naming a model that is gone is the whole point"))
  (testing ":only must name models of this schema"
    (let ((broken (make-schema :webhooks (list (make-webhook "h" "https://h" :only '(ghost)))
                               :models (list (make-model "m" :list nil)))))
      (ok (= (length (schema-errors broken)) 1))
      (ok (signals (check-schema broken) 'schema-error)))
    (ok (null (schema-errors (make-schema :webhooks (list (make-webhook "h" "https://h" :only '(m)))
                                          :models (list (make-model "m" :list nil))))))))

(deftest labels
  (testing "a model names the field that labels its contents"
    (let ((model (make-model "blog" :list (list (make-field :event-title :text)) :label 'event-title)))
      (ok (string= (model-label model) "eventTitle") "a symbol names the field as the field is named")
      (ok (null (model-label (make-model "tag" :list nil))) "and nothing is assumed without one")))
  (ok (signals (make-model "blog" :list nil :label 3) 'schema-error))
  (flet ((errors (fields label)
           (schema-errors (make-schema :models (list (make-model "m" :list fields :label label))))))
    (ok (null (errors (list (make-field :title :text)) :title)))
    (ok (null (errors (list (make-field :slug :slug :from :title) (make-field :title :text)) :slug)))
    (ok (= (length (errors (list (make-field :title :text)) :headline)) 1)
        "a field that is not there, removed or renamed without the label following")
    (ok (= (length (errors (list (make-field :body :richtext)) :body)) 1)
        "a field whose value is not a line of text")
    (ok (= (length (errors (list (make-field :tags :select :options '("a")) ) :tags)) 1)))
  (testing "it goes over the wire and back"
    (let* ((schema (make-schema :models (list (make-model "m" :list (list (make-field :title :text)) :label :title))))
           (obj (schema->jobject schema)))
      (ok (string= (jget (aref (jget obj "models") 0) "label") "title"))
      (ok (string= (model-label (schema-model (jobject->schema (parse-json (to-json obj))) "m")) "title"))
      (ng (nth-value 1 (jget (aref (jget (schema->jobject (make-schema :models (list (make-model "m" :list nil))))
                                         "models") 0)
                             "label"))
          "absent when there is none"))))

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
