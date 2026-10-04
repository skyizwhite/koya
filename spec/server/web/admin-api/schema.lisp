(defpackage #:koya-spec/server/web/admin-api/schema
  (:use #:cl #:rove)
  (:import-from #:koya-spec/server/web/api-support #:*management-key* #:test-schema #:request #:admin #:setup-api #:reset-api)
  (:import-from #:koya-server/infra/db/connection #:disconnect-db)
  (:import-from #:koya-core/schema #:make-field #:make-model #:make-schema #:make-webhook #:schema->jobject
                #:make-custom-field)
  (:import-from #:koya-core/json #:jobject #:jget)
  (:import-from #:koya-server/usecases/schema #:replace-schema))
(in-package #:koya-spec/server/web/admin-api/schema)

(setup (setup-api))

(teardown (disconnect-db))

(defhook :before (reset-api))

(deftest boolean-default
  (multiple-value-bind (status json)
      (admin :post "/admin/api/website/lists/blog" :body (jobject "data" (jobject "title" "Defaulted") "publish" t))
    (ok (= status 201))
    (ok (eq (jget json "published" "featured") t) "a :boolean with :default t starts true when not given"))
  (multiple-value-bind (status json)
      (admin :post "/admin/api/website/lists/blog" :body (jobject "data" (jobject "title" "Explicit" "featured" nil) "publish" t))
    (ok (= status 201))
    (ok (eq (jget json "published" "featured") nil) "an explicit false is kept")))

(deftest schema-endpoints
  (multiple-value-bind (status json) (admin :get "/admin/api/website/schema")
    (ok (= status 200))
    (ok (= (length (jget json "models")) 3)))
  (let ((new (make-schema :models (list (make-model "blog" :list (list (make-field :title :text)))))))
    (multiple-value-bind (status json) (admin :post "/admin/api/website/schema/plan" :body (schema->jobject new))
      (ok (= status 200))
      (ok (eq (jget json "destructive") t))
      (ok (plusp (length (jget json "changes")))))
    (multiple-value-bind (status json) (admin :put "/admin/api/website/schema" :body (schema->jobject new))
      (ok (= status 409))
      (ok (string= (jget json "error" "code") "destructive_changes"))
      (ok (plusp (length (jget json "error" "details")))))
    (multiple-value-bind (status json) (admin :get "/admin/api/website/schema")
      (ok (= status 200))
      (ok (= (length (jget json "models")) 3) "not applied")))
  (testing "non-destructive push applies without force"
    (let ((new (make-schema :webhooks (list (make-webhook "hook" "https://example.com/hook"))
                            :models (list (make-model "blog" :list (list (make-field :title :text :required t :unique t)
                                                                         (make-field :body :richtext)
                                                                         (make-field :featured :boolean :default t)
                                                                         (make-field :tags :reference :model "tag" :many t)
                                                                         (make-field :cover :media)
                                                                         (make-field :extra :text)))
                                          (make-model "tag" :list (list (make-field :name :text :required t)))
                                          (make-model "about" :object (list (make-field :body :richtext)))))))
      (multiple-value-bind (status json) (admin :put "/admin/api/website/schema" :body (schema->jobject new))
        (ok (= status 200))
        (ok (= (length (jget json "applied")) 1))
        (ok (string= (jget (aref (jget json "applied") 0) "op") "add_field")))
      (admin :put "/admin/api/website/schema" :body (schema->jobject (test-schema)) :query "force=true")))
  (testing "a management key reaches its own space and no other"
    (multiple-value-bind (status json) (admin :get "/admin/api/other/schema")
      (ok (= status 403))
      (ok (string= (jget json "error" "code") "forbidden")))
    (multiple-value-bind (status) (admin :put "/admin/api/other/schema" :body (schema->jobject (test-schema)))
      (ok (= status 403))))
  (testing "invalid schema is a 400"
    (multiple-value-bind (status json) (admin :put "/admin/api/website/schema" :body (jobject "koyaSchema" 1 "models" (vector (jobject "name" "Bad Name" "kind" "list"))))
      (ok (= status 400))
      (ok (string= (jget json "error" "code") "invalid_schema"))))
  (testing "malformed JSON is a 400"
    (multiple-value-bind (status json) (request :put "/admin/api/website/schema" :headers `(("authorization" . ,(format nil "Bearer ~a" *management-key*))) :body "not json")
      (ok (= status 400))
      (ok (string= (jget json "error" "code") "bad_json")))))

(deftest an-option-with-a-comma-is-refused-on-deploy-alone
  (let ((comma (make-schema :models (list (make-model "blog" :list
                                                      (list (make-field :title :text :required t :unique t)
                                                            (make-field :tone :select :options '("Red, dark" "Blue"))))))))
    (multiple-value-bind (status json) (admin :post "/admin/api/website/schema/plan" :body (schema->jobject comma))
      (ok (= status 400))
      (ok (string= (jget json "error" "code") "invalid_schema"))
      (ok (search "comma" (jget json "error" "message")) "the plan says why"))
    (multiple-value-bind (status json) (admin :put "/admin/api/website/schema" :body (schema->jobject comma) :query "force=true")
      (ok (= status 400) "nor is it deployed, forced or not")
      (ok (string= (jget json "error" "code") "invalid_schema")))
    (testing "a space already stored with one, or imported with one, is read as it is"
      (replace-schema "website" comma)
      (multiple-value-bind (status json) (admin :get "/admin/api/website/schema")
        (ok (= status 200))
        (ok (= (length (jget json "models")) 1)))
      (ok (= 200 (nth-value 0 (admin :get "/admin/api/website/lists/blog")))))))

(deftest a-tightened-option-waits-for-the-contents-to-fit
  (flet ((notes (&rest code-options)
           (make-schema :models (list (make-model "note" :list (list (make-field :title :text)
                                                                     (apply #'make-field :code :text code-options))))))
         (add-note (data &key publish)
           (jget (nth-value 1 (admin :post "/admin/api/website/lists/note"
                                     :body (jobject "data" data "publish" publish)))
                 "id"))
         (misfits (json path)
           (loop :for change :across (apply #'jget json path) :append (coerce (or (jget change "misfits") #()) 'list))))
    (replace-schema "website" (notes))
    (unwind-protect
         (let ((long (add-note (jobject "title" "Long" "code" "abcdefgh") :publish t))
               (none (add-note (jobject "title" "None")))
               (twin (add-note (jobject "title" "Twin" "code" "abcdefgh"))))
           (multiple-value-bind (status json) (admin :post "/admin/api/website/schema/plan"
                                                     :body (schema->jobject (notes :max-length 5)))
             (ok (= status 200))
             (ng (jget json "destructive") "tightening asks for no force")
             (ok (equal (sort (mapcar (lambda (m) (jget m "id")) (misfits json '("changes"))) #'string<)
                        (sort (list long twin) #'string<))
                 "the plan names every content whose value no longer fits")
             (ok (search "2 contents do not fit" (jget (aref (jget json "changes") 0) "description"))))
           (dolist (query '(nil "force=true"))
             (multiple-value-bind (status json) (admin :put "/admin/api/website/schema"
                                                       :body (schema->jobject (notes :max-length 5)) :query query)
               (ok (= status 409) (format nil "the deploy is refused~@[ with ~a~]" query))
               (ok (string= (jget json "error" "code") "contents_do_not_fit"))
               (ok (= (length (misfits json '("error" "details"))) 2))))
           (ok (plusp (length (jget (nth-value 1 (admin :post "/admin/api/website/schema/plan"
                                                         :body (schema->jobject (notes :max-length 5))))
                                    "changes")))
               "and nothing is applied")
           (testing "unique and required are checked the same way"
             (ok (= 2 (length (misfits (nth-value 1 (admin :post "/admin/api/website/schema/plan"
                                                          :body (schema->jobject (notes :unique t))))
                                       '("changes"))))
                 "the two contents that share a value")
             (ok (equal (mapcar (lambda (m) (jget m "id"))
                                (misfits (nth-value 1 (admin :post "/admin/api/website/schema/plan"
                                                             :body (schema->jobject (notes :required t))))
                                         '("changes")))
                        (list none))
                 "the content without one"))
           (testing "once they fit, the deploy goes through"
             (admin :patch (format nil "/admin/api/website/lists/note/~a" long) :body (jobject "data" (jobject "code" "abc")))
             (admin :post (format nil "/admin/api/website/lists/note/~a/publish" long))
             (admin :patch (format nil "/admin/api/website/lists/note/~a" twin) :body (jobject "data" (jobject "code" "xyz")))
             (ok (= 200 (admin :put "/admin/api/website/schema" :body (schema->jobject (notes :max-length 5))))))
           (testing "a required field added to a model with contents waits for them too"
             (let ((with-lede (make-schema :models (list (make-model "note" :list
                                                                     (list (make-field :title :text)
                                                                           (make-field :code :text :max-length 5)
                                                                           (make-field :lede :text :required t)))))))
               (multiple-value-bind (status json) (admin :put "/admin/api/website/schema" :body (schema->jobject with-lede))
                 (ok (= status 409))
                 (ok (= (length (misfits json '("error" "details"))) 3)
                     "every stored version of every content lacks it")))))
      (replace-schema "website" (test-schema)))))

(deftest misfits-are-told-first-and-not-of-contents-that-go
  (flet ((notes (kind &rest code-options)
           (make-schema :models (list (make-model "note" kind (list (make-field :title :text)
                                                                    (apply #'make-field :code :text code-options)))))))
    (replace-schema "website" (notes :list))
    (unwind-protect
         (progn
           (admin :post "/admin/api/website/lists/note" :body (jobject "data" (jobject "title" "Long" "code" "abcdefgh")))
           (testing "a deploy that could never go through says why before it asks for force"
             (let ((without-title (make-schema :models (list (make-model "note" :list
                                                                         (list (make-field :code :text :max-length 5)))))))
               (multiple-value-bind (status json) (admin :put "/admin/api/website/schema" :body (schema->jobject without-title))
                 (ok (= status 409))
                 (ok (string= (jget json "error" "code") "contents_do_not_fit")))))
           (testing "a model made anew is not checked, as its contents go"
             (ok (= 200 (admin :put "/admin/api/website/schema" :body (schema->jobject (notes :object :max-length 5))
                                                                :query "force=true")))))
      (replace-schema "website" (test-schema)))))

(deftest a-custom-field-goes-over-the-api
  (flet ((cards (&rest title-options)
           (make-schema :custom-fields (list (make-custom-field "card" (list (apply #'make-field :title :text title-options))))
                        :models (list (make-model "note" :list (list (make-field :card :custom :custom-field "card")))))))
    (replace-schema "website" (cards))
    (unwind-protect
         (progn
           (multiple-value-bind (status json) (admin :get "/admin/api/website/schema")
             (ok (= status 200))
             (ok (string= (jget (aref (jget json "customFields") 0) "name") "card") "it is read back"))
           (admin :post "/admin/api/website/lists/note" :body (jobject "data" (jobject "card" (jobject "title" "abcdefgh"))))
           (multiple-value-bind (status json) (admin :post "/admin/api/website/schema/plan"
                                                     :body (schema->jobject (cards :max-length 5)))
             (ok (= status 200))
             (let ((misfit (loop :for change :across (jget json "changes")
                                 :thereis (and (jget change "misfits") (aref (jget change "misfits") 0)))))
               (ok misfit "tightening a field inside is checked against stored contents")
               (ok (string= (jget misfit "field") "card.title") "and the misfit says where"))))
      (replace-schema "website" (test-schema)))))

(deftest a-field-tightened-inside-is-checked-alone
  (flet ((cards (&rest fields)
           (make-schema :custom-fields (list (make-custom-field "card" fields))
                        :models (list (make-model "note" :list (list (make-field :card :custom :custom-field "card"))))))
         (required-cards (&rest fields)
           (make-schema :custom-fields (list (make-custom-field "card" fields))
                        :models (list (make-model "note" :list (list (make-field :card :custom :custom-field "card" :required t)))))))
    (replace-schema "website" (cards (make-field :title :text) (make-field :image :text)))
    (unwind-protect
         (progn
           (admin :post "/admin/api/website/lists/note" :body (jobject "data" (jobject "card" (jobject "title" "T" "image" "I"))))
           (multiple-value-bind (status json) (admin :post "/admin/api/website/schema/plan"
                                                     :body (schema->jobject (required-cards (make-field :title :text))))
             (ok (= status 200))
             (ok (every (lambda (c) (null (jget c "misfits"))) (jget json "changes"))
                 "a custom field made required is checked with what the same deploy removes from it gone"))
           (admin :post "/admin/api/website/lists/note" :body (jobject "data" (jobject "card" (jobject))))
           (admin :post "/admin/api/website/lists/note" :body (jobject "data" (jobject "card" (jobject "image" "Only"))))
           (multiple-value-bind (status json) (admin :put "/admin/api/website/schema"
                                                     :body (schema->jobject (cards (make-field :title :text :required t)))
                                                     :query "force=true")
             (ok (= status 200) "a field made required inside is checked alone, not with one the same deploy removes")
             (ng (jget json "error"))))
      (replace-schema "website" (test-schema)))))
