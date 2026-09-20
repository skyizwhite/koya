(defpackage #:koya-tests/config
  (:use #:cl #:rove)
  (:import-from #:koya/config
                #:defspace #:defmodel #:webhook #:current-schema #:clear-schema #:find-space #:find-model)
  (:import-from #:koya/core/schema
                #:schema-space #:space-models #:space-webhooks #:space-model
                #:model-field #:model-kind #:field-option #:field-type #:schema-error
                #:model-preview-url #:model-public-url))
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
  (defmodel (website about) (:kind :object
                             :preview-url (format nil "~a/about?draft-key={DRAFT_KEY}" "https://x")
                             :public-url "https://x/about")
    (body :richtext))
  (let* ((schema (current-schema))
         (space (schema-space schema "website"))
         (blog (space-model space "blog")))
    (ok (equal (space-webhooks space) '((:label "https://example.com/hook" :url "https://example.com/hook"
                                         :events (:publish :unpublish :delete))))
        "a bare URL becomes a webhook with default events")
    (ok (equal (mapcar #'koya/core/schema:model-name (space-models space)) '("blog" "tag" "about")))
    (ok (eq (model-kind (space-model space "tag")) :list) "kind defaults to :list")
    (ok (eq (model-kind (space-model space "about")) :object))
    (ok (string= (model-preview-url (space-model space "about")) "https://x/about?draft-key={DRAFT_KEY}") "options are evaluated")
    (ok (string= (model-public-url (space-model space "about")) "https://x/about"))
    (ok (null (model-preview-url blog)))
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
  (ok (equal (mapcar #'koya/core/schema:webhook-url (space-webhooks (find-space 'website))) '("https://x"))))

(deftest webhooks-dsl
  (clear-schema)
  (defspace website :webhooks (list (webhook "revalidate" "https://site/revalidate")))
  (defmodel (website blog) (:webhooks (list (webhook "preview" "https://preview/hook" :events '(:draft))
                                             (webhook "index" "https://search/hook" :events '("publish" :delete))))
    (title :text))
  (let* ((space (schema-space (current-schema) "website"))
         (blog (space-model space "blog")))
    (ok (equal (space-webhooks space) '((:label "revalidate" :url "https://site/revalidate" :events (:publish :unpublish :delete)))))
    (ok (equal (mapcar #'koya/core/schema:webhook-label (koya/core/schema:model-webhooks blog)) '("preview" "index")))
    (ok (equal (koya/core/schema:webhook-events (second (koya/core/schema:model-webhooks blog))) '(:publish :delete))
        "events accept strings and keep canonical order"))
  (ok (signals (eval '(defmodel (website blog) (:webhooks (list (webhook "x" "https://x" :events '(:nope)))) (title :text)))
               'koya/core/schema:schema-error)
      "unknown events are rejected"))

(deftest errors
  (ok (signals (eval '(defmodel (nowhere blog) () (title :text))) 'error) "space must exist")
  (defspace website)
  (defmodel (website blog) () (tags :reference :model ghost))
  (ok (signals (current-schema) 'schema-error) "dangling reference is caught on current-schema"))
