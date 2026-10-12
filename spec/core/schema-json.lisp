(defpackage #:koya-spec/core/schema-json
  (:use #:cl #:rove)
  (:import-from #:koya-core/schema
                #:make-field #:make-model #:make-schema #:field-name #:field-type #:field-option
                #:field-was #:model-field #:model-was #:schema-model #:schema-webhooks
                #:model-preview-url #:model-public-url #:model-label #:model-options #:schema-error
                #:custom-field-name #:field-fields #:field-row-kinds #:field-key)
  (:import-from #:koya-core/schema-json
                #:schema->jobject #:jobject->schema #:change->jobject)
  (:import-from #:koya-core/diff
                #:diff-schemas)
  (:import-from #:koya-core/json
                #:to-json #:parse-json #:jget)
  (:import-from #:koya-spec/core/schema
                #:sample-schema #:with-seo #:blocks-schema))
(in-package #:koya-spec/core/schema-json)

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
      (ok (eq (field-type (model-field blog :slug)) :slug)))
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
                    "{\"koyaSchema\": 1, \"models\": [{\"name\": \"m\", \"kind\": \"list\", \"fields\": [{\"name\": \"f\", \"type\": \"select\", \"options\": \"abc\"}]}]}"
                    "{\"koyaSchema\": 1, \"models\": [{\"name\": \"m\", \"kind\": \"list\", \"fields\": [{\"name\": \"t\", \"type\": \"text\"}, {\"name\": \"s\", \"type\": \"slug\", \"from\": \"t\"}]}]}"
                    "{\"koyaSchema\": 1, \"models\": [{\"name\": \"m\", \"kind\": \"list\", \"fields\": [{\"name\": \"s\", \"type\": \"slug\", \"unique\": true}]}]}"))
      (ok (signals (jobject->schema (parse-json json)) 'schema-error) json))
    (ok (signals (jobject->schema (parse-json "{\"koyaSchema\": 1, \"models\": [{\"name\": \"about\", \"kind\": \"object\", \"previewUrl\": \"javascript:alert(1)\"}]}"))
                 'schema-error)
        "a URL template that is not a web address")
    (ok (signals (jobject->schema (parse-json "{\"koyaSchema\": 1, \"webhooks\": [\"https://old\"]}"))
                 'schema-error)
        "a bare URL is not a webhook on the wire either")
    (ok (signals (jobject->schema (parse-json "{\"koyaSchema\": 1, \"webhooks\": [{\"url\": \"https://m\", \"only\": null}]}"))
                 'schema-error)
        "nor is an only of null the model \"null\"")))

(deftest webhooks-written-by-older-schemas
  (let ((wire (jobject->schema (parse-json "{\"koyaSchema\": 1, \"webhooks\": [{\"label\": \"new\", \"url\": \"https://new\", \"events\": [\"draft\"]}, {\"url\": \"https://m\", \"only\": [\"m\"]}], \"models\": [{\"name\": \"m\", \"kind\": \"list\", \"webhooks\": [{\"url\": \"https://old\"}]}]}"))))
    (ok (equal (first (schema-webhooks wire)) '(:label "new" :url "https://new"))
        "the events older schemas carried are dropped on load")
    (ok (equal (second (schema-webhooks wire)) '(:label "https://m" :url "https://m" :only ("m")))
        "a label defaults to the URL on the wire, and :only survives it")
    (ok (null (model-options (schema-model wire "m")))
        "a webhooks key left on a model by an older schema is ignored")))

(deftest renames-on-the-wire
  (ok (signals (jobject->schema (parse-json "{\"koyaSchema\": 1, \"models\": [{\"name\": \"m\", \"kind\": \"list\", \"was\": 5}]}"))
               'schema-error)
      "a was that is not a name at all is refused, not left to signal elsewhere")
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

(deftest a-label-on-the-wire
  (let* ((schema (make-schema :models (list (make-model "m" :list (list (make-field :title :text)) :label :title))))
         (obj (schema->jobject schema)))
    (ok (string= (jget (aref (jget obj "models") 0) "label") "title"))
    (ok (string= (model-label (schema-model (jobject->schema (parse-json (to-json obj))) "m")) "title"))
    (ng (nth-value 1 (jget (aref (jget (schema->jobject (make-schema :models (list (make-model "m" :list nil))))
                                       "models") 0)
                           "label"))
        "absent when there is none")))

(deftest options-are-written-in-one-order
  (flet ((json (field)
           (to-json (schema->jobject (make-schema :models (list (make-model "m" :list (list field))))))))
    (ok (string= (json (make-field :title :text :required t :max-length 10 :unique t))
                 (json (make-field :title :text :unique t :max-length 10 :required t)))
        "however the field was given its options")))

(deftest a-help-text-on-the-wire
  (let* ((schema (make-schema :models (list (make-model "m" :list (list (make-field :cover :media :help "1200x630"))))))
         (obj (schema->jobject schema))
         (field (aref (jget (aref (jget obj "models") 0) "fields") 0)))
    (ok (string= (jget field "help") "1200x630"))
    (ok (string= (field-option (model-field (schema-model (jobject->schema (parse-json (to-json obj))) "m") :cover) :help)
                 "1200x630"))))

(deftest custom-fields-on-the-wire
  (let* ((obj (schema->jobject (with-seo)))
         (json (to-json obj))
         (back (jobject->schema (parse-json json))))
    (ok (search "\"customFields\":[{\"name\":\"seo\",\"fields\":[" json))
    (ok (search "{\"name\":\"meta\",\"type\":\"custom\",\"customField\":\"seo\"}" json)
        "a model names it and does not repeat its fields")
    (ok (equal (mapcar #'field-name (field-fields (model-field (schema-model back "blog") :meta)))
               '("title" "image" "kind")))
    (ok (string= json (to-json (schema->jobject back))) "and the round trip is stable"))
  (ng (search "customFields" (to-json (schema->jobject (make-schema)))) "absent when there are none"))

(deftest repeaters-on-the-wire
  (let* ((json (to-json (schema->jobject (blocks-schema))))
         (back (jobject->schema (parse-json json))))
    (ok (search "{\"name\":\"blocks\",\"type\":\"repeater\",\"customFields\":[\"heading\",\"body\"]}" json))
    (ok (equal (mapcar #'custom-field-name (field-row-kinds (model-field (schema-model back "page") :blocks)))
               '("heading" "body")))))

(deftest a-schema-read-from-json-interns-its-fields-keywords
  (let* ((schema (jobject->schema (parse-json "{\"koyaSchema\": 1,
                                                \"customFields\": [{\"name\": \"card\", \"fields\": [{\"name\": \"cardCaptionQq\", \"type\": \"text\"}]}],
                                                \"models\": [{\"name\": \"page\", \"kind\": \"list\", \"fields\": [
                                                  {\"name\": \"pageWidthQq\", \"type\": \"number\"},
                                                  {\"name\": \"card\", \"type\": \"custom\", \"customField\": \"card\"}]}]}")))
         (model (schema-model schema "page")))
    (ok (eq (field-key (model-field model "pageWidthQq")) (find-symbol "PAGE-WIDTH-QQ" :keyword))
        "a model's fields")
    (ok (eq (field-key (first (field-fields (model-field model "card")))) :card-caption-qq)
        "and those of the fields inside a custom field")))

(deftest a-deploy-s-changes-on-the-wire
  (flet ((blog (&rest options)
           (make-schema :models (list (make-model "blog" :list (list (apply #'make-field :title :text options)
                                                                      (make-field :body :richtext)))))))
    (let ((change (first (diff-schemas (blog) (make-schema :models (list (make-model "blog" :list (list (make-field :title :text)
                                                                                                     (make-field :body :textarea)))))))))
      (ok (string= (jget (change->jobject change) "op") "change_field_type") "an op is written in snake case")
      (ok (string= (jget (change->jobject change) "path") "blog.body"))
      (ok (eq (jget (change->jobject change) "destructive") t))
      (ok (search "richtext -> textarea" (jget (change->jobject change) "description"))))
    (let ((change (append (first (diff-schemas (blog) (blog :required t)))
                          (list :misfits (list (list :id "a" :field "title" :version "draft" :message "is required")
                                               (list :id "b" :field "title" :version "published" :message "is required"))))))
      (let ((misfits (jget (change->jobject change) "misfits")))
        (ok (= (length misfits) 2) "the contents that do not fit are listed")
        (ok (equal (jget (aref misfits 0) "id") "a"))
        (ok (equal (jget (aref misfits 0) "field") "title"))
        (ok (equal (jget (aref misfits 0) "version") "draft"))
        (ok (equal (jget (aref misfits 0) "message") "is required"))))
    (ng (nth-value 1 (jget (change->jobject (first (diff-schemas (blog) (blog :required t)))) "misfits"))
        "and a change with none has no list")))
