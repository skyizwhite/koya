(defpackage #:koya-tests/config
  (:use #:cl #:rove)
  (:import-from #:koya/config
                #:defspace #:defmodel #:current-schema #:clear-schema #:find-space #:find-model)
  (:import-from #:koya/core/schema
                #:schema-space #:space-models #:space-webhooks #:space-model
                #:model-field #:model-kind #:field-option #:field-type #:schema-error))
(in-package #:koya-tests/config)

(defhook :before (clear-schema))
(defhook :after (clear-schema))

(deftest dsl
  (defspace website :webhooks (list "https://example.com/hook"))
  (defmodel (website blog) (:kind :list)
    (title        :text :required t :max-length 100)
    (tags         :reference :model tag :many t)
    (category     :select :options ("news" "tech"))
    (event-at :datetime))
  (defmodel (website tag) ()
    (name :text :required t))
  (defmodel (website about) (:kind :object)
    (body :richtext))
  (let* ((schema (current-schema))
         (space (schema-space schema "website"))
         (blog (space-model space "blog")))
    (ok (equal (space-webhooks space) '("https://example.com/hook")))
    (ok (equal (mapcar #'koya/core/schema:model-name (space-models space)) '("blog" "tag" "about")))
    (ok (eq (model-kind (space-model space "tag")) :list) "kind defaults to :list")
    (ok (eq (model-kind (space-model space "about")) :object))
    (ok (= (field-option (model-field blog "title") :max-length) 100))
    (ok (string= (field-option (model-field blog "tags") :model) "tag"))
    (ok (equal (field-option (model-field blog "category") :options) '("news" "tech")))
    (ok (eq (field-type (model-field blog "eventAt")) :datetime))))

(deftest redefinition
  (defspace website)
  (defmodel (website blog) () (title :text))
  (defmodel (website blog) () (title :text) (body :richtext))
  (ok (= (length (space-models (find-space 'website))) 1) "redefining replaces, does not duplicate")
  (ok (model-field (find-model 'website 'blog) 'body))
  (defspace website :webhooks '("https://x"))
  (ok (= (length (space-models (find-space 'website))) 1) "redefining a space keeps its models")
  (ok (equal (space-webhooks (find-space 'website)) '("https://x"))))

(deftest errors
  (ok (signals (eval '(defmodel (nowhere blog) () (title :text))) 'error) "space must exist")
  (defspace website)
  (defmodel (website blog) () (tags :reference :model ghost))
  (ok (signals (current-schema) 'schema-error) "dangling reference is caught on current-schema"))
