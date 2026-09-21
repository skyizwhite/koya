(defpackage #:koya-tests/core/schema
  (:use #:cl #:rove)
  (:import-from #:koya/core/schema
                #:make-field #:make-model #:make-space #:make-schema
                #:field-name #:field-type #:field-option
                #:model-field #:model-kind #:space-model #:schema-space #:space-webhooks
                #:model-preview-url #:model-public-url #:model-webhooks #:make-webhook
                #:schema-error #:schema-errors #:check-schema
                #:schema->jobject #:jobject->schema)
  (:import-from #:koya/core/json
                #:to-json #:parse-json #:jget))
(in-package #:koya-tests/core/schema)

(defun sample-schema ()
  (make-schema
   (list (make-space "website"
                     :webhooks (list (make-webhook "hook" "https://example.com/hook" :events '(:publish :unpublish :delete)))
                     :models (list (make-model "blog" :list
                                               (list (make-field :title :text :required t :max-length 100)
                                                     (make-field :slug :slug :from :title :unique t)
                                                     (make-field :content :richtext)
                                                     (make-field :tags :reference :model "tag" :many t)
                                                     (make-field :event-at :datetime)))
                                   (make-model "tag" :list (list (make-field :name :text :required t)))
                                   (make-model "about" :object (list (make-field :body :richtext))
                                               :preview-url "https://x/about?draft-key={DRAFT_KEY}"
                                               :public-url "https://x/about"))))))

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
    (ok (signals (make-space "s" :webhooks "https://x") 'schema-error) "webhooks must be a list")
    (ok (signals (make-webhook "" "https://x" :events '(:publish :unpublish :delete)) 'schema-error) "label needed")
    (ok (signals (make-webhook "x" "" :events '(:publish :unpublish :delete)) 'schema-error) "url needed")
    (ok (signals (make-webhook "x" "https://x") 'schema-error) "events must be given")
    (ok (signals (make-webhook "x" "https://x" :events '()) 'schema-error) "and not empty")
    (ok (signals (make-space "s" :webhooks '("https://x")) 'schema-error) "a bare URL is not a webhook")
    (ok (signals (make-webhook "x" "https://x" :events '(:publish :bogus)) 'schema-error) "unknown event")
    (ok (signals (make-space "s" :webhooks (list (make-webhook "a" "https://x" :events '(:publish :unpublish :delete)) (make-webhook "a" "https://y" :events '(:publish :unpublish :delete)))) 'schema-error)
        "labels are unique within a space")
    (ok (equal (make-webhook "x" "https://x" :events '(:draft "publish" :publish)) '(:label "x" :url "https://x" :events (:publish :draft)))
        "events are deduplicated and ordered")
    (let ((wire (jobject->schema (parse-json "{\"koyaSchema\": 1, \"spaces\": [{\"name\": \"s\", \"webhooks\": [{\"label\": \"new\", \"url\": \"https://new\", \"events\": [\"draft\"]}], \"models\": [{\"name\": \"m\", \"kind\": \"list\", \"webhooks\": [{\"url\": \"https://m\", \"events\": [\"publish\"]}]}]}]}"))))
      (ok (equal (space-webhooks (schema-space wire "s")) '((:label "new" :url "https://new" :events (:draft)))))
      (ok (equal (model-webhooks (space-model (schema-space wire "s") "m"))
                 '((:label "https://m" :url "https://m" :events (:publish))))
          "a label defaults to the URL on the wire"))
    (dolist (json '("{\"koyaSchema\": 1, \"spaces\": [{\"name\": \"s\", \"webhooks\": [\"https://old\"]}]}"
                    "{\"koyaSchema\": 1, \"spaces\": [{\"name\": \"s\", \"webhooks\": [{\"label\": \"x\", \"url\": \"https://x\"}]}]}"))
      (ok (signals (jobject->schema (parse-json json)) 'schema-error) "webhooks on the wire need events too"))
    (ok (signals (make-model (format nil "blog~%") :list nil) 'schema-error) "no trailing newline"))
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
    (ok (equal (space-webhooks (schema-space back :website))
               '((:label "hook" :url "https://example.com/hook" :events (:publish :unpublish :delete)))))
    (ok (search "\"webhooks\":[{\"label\":\"hook\"" json) "webhooks are objects on the wire")
    (let ((blog (space-model (schema-space back :website) :blog)))
      (ok (= (field-option (model-field blog :title) :max-length) 100))
      (ok (field-option (model-field blog :tags) :many))
      (ok (string= (field-option (model-field blog :tags) :model) "tag"))
      (ok (string= (field-option (model-field blog :slug) :from) "title")))
    (let ((about (space-model (schema-space back :website) :about)))
      (ok (string= (model-preview-url about) "https://x/about?draft-key={DRAFT_KEY}"))
      (ok (string= (model-public-url about) "https://x/about"))
      (ok (search "\"previewUrl\"" json)))
    (ok (null (model-public-url (space-model (schema-space back :website) :blog))) "absent when not set")
    (testing "round trip is stable"
      (ok (string= json (to-json (schema->jobject back))))))
  (testing "rejects bad input"
    (ok (signals (jobject->schema (parse-json "{\"koyaSchema\": 2, \"spaces\": []}")) 'schema-error))
    (ok (signals (jobject->schema (parse-json "{\"koyaSchema\": 1, \"spaces\": [{\"name\": \"s\", \"models\": [{\"name\": \"m\", \"kind\": \"list\", \"fields\": [{\"name\": \"f\", \"type\": \"nope\"}]}]}]}")) 'schema-error))
    (ok (signals (jobject->schema (parse-json "[]")) 'schema-error))
    (dolist (json '("{\"koyaSchema\": 1, \"spaces\": [{\"name\": 5}]}"
                    "{\"koyaSchema\": 1, \"spaces\": [{\"name\": \"s\", \"webhooks\": \"https://x\"}]}"
                    "{\"koyaSchema\": 1, \"spaces\": [{\"name\": \"s\", \"models\": [{\"name\": \"m\", \"kind\": \"list\", \"fields\": 5}]}]}"
                    "{\"koyaSchema\": 1, \"spaces\": [{\"name\": \"s\", \"models\": [{\"name\": \"m\", \"kind\": \"LIST\"}]}]}"
                    "{\"koyaSchema\": 1, \"spaces\": [{\"name\": \"s\", \"models\": [{\"name\": \"m\", \"kind\": \"list\", \"fields\": [{\"name\": \"f\", \"type\": \"text\", \"pattern\": \"(\"}]}]}]}"
                    "{\"koyaSchema\": 1, \"spaces\": [{\"name\": \"s\", \"models\": [{\"name\": \"m\", \"kind\": \"list\", \"fields\": [{\"name\": \"f\", \"type\": \"text\", \"bogus\": 1}]}]}]}"
                    "{\"koyaSchema\": 1, \"spaces\": [{\"name\": \"s\", \"models\": [{\"name\": \"m\", \"kind\": \"list\", \"fields\": [{\"name\": \"f\", \"type\": \"select\", \"options\": \"abc\"}]}]}]}"))
      (ok (signals (jobject->schema (parse-json json)) 'schema-error) json))))
