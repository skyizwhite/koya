(defpackage #:koya-tests/config
  (:use #:cl #:rove)
  (:import-from #:koya/config
                #:defwebhooks #:defmodel #:webhook #:current-schema #:clear-schema #:find-model)
  (:import-from #:koya/core/schema
                #:schema-models #:schema-webhooks #:schema-model
                #:model-field #:model-kind #:field-option #:field-type #:schema-error
                #:model-preview-url #:model-public-url))
(in-package #:koya-tests/config)

(defhook :before (clear-schema))
(defhook :after (clear-schema))

(deftest dsl
  (defwebhooks (webhook "hook" "https://example.com/hook"))
  (defmodel blog (:kind :list)
    (title        :text :required t :max-length 100)
    (tags         :reference :model tag :many t)
    (category     :select :options ("news" "tech"))
    (event-at :datetime))
  (defmodel tag (:kind :list)
    (name :text :required t))
  (defmodel about (:kind :object
                   :preview-url (format nil "~a/about?draft-key={DRAFT_KEY}" "https://x")
                   :public-url "https://x/about")
    (body :richtext))
  (let* ((schema (current-schema))
         (blog (schema-model schema "blog")))
    (ok (equal (schema-webhooks schema) '((:label "hook" :url "https://example.com/hook"))))
    (ok (equal (mapcar #'koya/core/schema:model-name (schema-models schema)) '("blog" "tag" "about")))
    (ok (eq (model-kind (schema-model schema "tag")) :list))
    (ok (signals (macroexpand-1 '(defmodel nokind () (title :text))) 'error) ":kind is required")
    (ok (signals (macroexpand-1 '(defmodel badkind (:kind :table) (title :text))) 'error) ":kind must be :list or :object")
    (ok (eq (model-kind (schema-model schema "about")) :object))
    (ok (string= (model-preview-url (schema-model schema "about")) "https://x/about?draft-key={DRAFT_KEY}") "options are evaluated")
    (ok (string= (model-public-url (schema-model schema "about")) "https://x/about"))
    (ok (null (model-preview-url blog)))
    (ok (= (field-option (model-field blog "title") :max-length) 100))
    (ok (string= (field-option (model-field blog "tags") :model) "tag"))
    (ok (equal (field-option (model-field blog "category") :options) '("news" "tech")))
    (ok (eq (field-type (model-field blog "eventAt")) :datetime))))

(deftest redefinition
  (defmodel blog (:kind :list) (title :text))
  (defmodel blog (:kind :list) (title :text) (body :richtext))
  (ok (= (length (schema-models (current-schema))) 1) "redefining replaces, does not duplicate")
  (ok (model-field (find-model 'blog) 'body))
  (defwebhooks (webhook "x" "https://x"))
  (ok (= (length (schema-models (current-schema))) 1) "setting the webhooks keeps the models")
  (ok (equal (mapcar #'koya/core/schema:webhook-url (schema-webhooks (current-schema))) '("https://x"))))

(deftest renaming-a-model-in-the-repl
  (defmodel post (:kind :list) (title :text) (lede :text))
  (ok (equal (mapcar #'koya/core/schema:model-name (schema-models (current-schema))) '("post")))
  ;; the same form, edited into its renamed self and evaluated again
  (defmodel article (:kind :list :was post) (title :text) (subtitle :text :was lede))
  (let ((models (schema-models (current-schema))))
    (ok (equal (mapcar #'koya/core/schema:model-name models) '("article"))
        "the definition it renames goes with it, or the schema would declare both")
    (ok (string= (koya/core/schema:model-was (first models)) "post")
        "and the deploy is still told where the contents are")
    (ok (string= (koya/core/schema:field-was (model-field (first models) "subtitle")) "lede")))
  (testing "a model that is still declared is still an error"
    (defmodel post (:kind :list) (title :text))
    (ok (signals (current-schema) 'schema-error))))

(deftest webhooks-dsl
  (clear-schema)
  (defwebhooks (webhook "revalidate" "https://site/revalidate")
               (webhook "preview" "https://preview/hook" :only 'blog)
               (webhook "index" "https://search/hook" :only '(blog tag)))
  (ok (signals (eval '(defwebhooks "https://x")) 'koya/core/schema:schema-error) "a bare URL is not a webhook")
  (defmodel blog (:kind :list) (title :text))
  (defmodel tag (:kind :list) (name :text))
  (let ((hooks (schema-webhooks (current-schema))))
    (ok (equal (mapcar #'koya/core/schema:webhook-label hooks) '("revalidate" "preview" "index")))
    (ok (null (koya/core/schema:webhook-only (first hooks))) "no :only means every model")
    (ok (equal (koya/core/schema:webhook-only (second hooks)) '("blog")))
    (ok (equal (koya/core/schema:webhook-only (third hooks)) '("blog" "tag"))))
  (testing ":only is checked against the models, once the schema is whole"
    (defwebhooks (webhook "ghost" "https://g" :only 'nowhere))
    (ok (signals (current-schema) 'schema-error)))
  (ok (signals (eval '(webhook "x" "https://x" :events '(:publish))) 'error)
      "the old :events argument is refused rather than ignored")
  (ok (signals (macroexpand-1 '(defmodel m (:kind :list :webhooks nil) (title :text))) 'error)
      "a model no longer carries webhooks"))

(deftest errors
  (defmodel blog (:kind :list) (tags :reference :model ghost))
  (ok (signals (current-schema) 'schema-error) "dangling reference is caught on current-schema"))
