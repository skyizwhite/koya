(defpackage #:koya-spec/core/diff
  (:use #:cl #:rove)
  (:import-from #:koya-core/schema
                #:make-field #:make-model #:make-schema #:make-webhook #:make-custom-field)
  (:import-from #:koya-core/diff
                #:diff-schemas
                #:destructive-changes-p
                #:tightened-change-p
                #:format-change
                #:change->jobject)
  (:import-from #:koya-core/json
                #:jget))
(in-package #:koya-spec/core/diff)

(defun schema-a ()
  (make-schema :models (list (make-model "blog" :list
                                         (list (make-field :title :text :required t)
                                               (make-field :body :richtext)))
                             (make-model "about" :object (list (make-field :body :richtext))))))

(defun schema-b ()
  (make-schema :webhooks (list (make-webhook "x" "https://x"))
               :models (list (make-model "blog" :list
                                         (list (make-field :title :text :required t :max-length 50)
                                               (make-field :body :textarea)
                                               (make-field :event-at :datetime)))
                             (make-model "tag" :list (list (make-field :name :text))))))

(defun ops (changes) (mapcar (lambda (c) (getf c :op)) changes))

(deftest no-changes
  (ok (null (diff-schemas (schema-a) (schema-a)))))

(deftest model-options
  (let* ((with-url (make-schema :models (list (make-model "blog" :list (list (make-field :title :text :required t)
                                                                             (make-field :body :richtext))
                                                          :public-url "https://x/blog/{CONTENT_ID}")
                                              (make-model "about" :object (list (make-field :body :richtext))))))
         (changes (diff-schemas (schema-a) with-url)))
    (ok (equal (ops changes) '(:change-model-options)))
    (ng (destructive-changes-p changes))
    (ok (search "options changed" (format-change (first changes))))))

(deftest a-label-is-an-option
  (let* ((labelled (make-schema :models (list (make-model "blog" :list (list (make-field :title :text :required t)
                                                                             (make-field :body :richtext))
                                                          :label :title)
                                              (make-model "about" :object (list (make-field :body :richtext))))))
         (changes (diff-schemas (schema-a) labelled)))
    (ok (equal (ops changes) '(:change-model-options)))
    (ng (destructive-changes-p changes) "it changes what the admin UI shows, not what is stored")
    (ok (search "label" (format-change (first changes))))))

(deftest a-reference-pointed-at-another-model-is-retyped
  (flet ((blog (target &rest options)
           (make-schema :models (list (make-model "tag" :list (list (make-field :name :text)))
                                      (make-model "cat" :list (list (make-field :name :text)))
                                      (make-model "blog" :list
                                                  (list (apply #'make-field :tag :reference :model target options)))))))
    (let ((changes (diff-schemas (blog "tag") (blog "cat"))))
      (ok (equal (ops changes) '(:change-field-type))
          "the stored ids name contents of the old model, so they are values of another type")
      (ok (destructive-changes-p changes))
      (ok (search "reference to tag -> reference to cat" (format-change (first changes)))))
    (let ((changes (diff-schemas (blog "tag") (blog "cat" :many t :required t))))
      (ok (equal (ops changes) '(:change-field-type)) "options changed with it go with the values"))
    (ng (diff-schemas (blog "tag") (blog "tag")) "the same model is no change")
    (let* ((renamed (make-schema :models (list (make-model "label" :list (list (make-field :name :text)) :was 'tag)
                                               (make-model "cat" :list (list (make-field :name :text)))
                                               (make-model "blog" :list
                                                           (list (make-field :tag :reference :model "label"))))))
           (changes (diff-schemas (blog "tag") renamed)))
      (ng (find :change-field-type (ops changes))
          "following the model it points at through a rename keeps the ids, which the rename carries")
      (ng (destructive-changes-p changes)))))

(deftest field-options
  (flet ((blog (&rest title-options)
           (make-schema :models (list (make-model "blog" :list
                                                  (list (apply #'make-field :title :text title-options))))))
         (only (changes) (progn (ok (= (length changes) 1)) (first changes))))
    (testing "case-only changes are seen"
      (let ((change (only (diff-schemas (blog :pattern "^[A-Z]") (blog :pattern "^[a-z]")))))
        (ok (eq (getf change :op) :change-field-options))
        (ok (tightened-change-p change) "a different pattern can reject existing content")))
    (testing "loosening is not tightening"
      (ng (tightened-change-p (only (diff-schemas (blog :max-length 50) (blog :max-length 100)))))
      (ng (tightened-change-p (only (diff-schemas (blog :required t) (blog))))))
    (testing "tightening is seen, and is not destructive: the server checks what is stored instead of asking for force"
      (ok (tightened-change-p (only (diff-schemas (blog) (blog :required t)))))
      (ok (tightened-change-p (only (diff-schemas (blog :max-length 100) (blog :max-length 50)))))
      (ok (tightened-change-p (only (diff-schemas (blog) (blog :unique t)))))
      (ng (destructive-changes-p (diff-schemas (blog) (blog :required t))))
      (ok (search "options tightened" (format-change (only (diff-schemas (blog) (blog :required t)))))))
    (testing "changing single/many and dropping select options is tightening"
      (flet ((sel (&rest options)
               (make-schema :models (list (make-model "blog" :list
                                                      (list (apply #'make-field :cat :select options)))))))
        (ok (tightened-change-p (only (diff-schemas (sel :options '("a" "b") :many t) (sel :options '("a" "b"))))))
        (ok (tightened-change-p (only (diff-schemas (sel :options '("a" "b")) (sel :options '("a"))))))
        (ng (tightened-change-p (only (diff-schemas (sel :options '("a")) (sel :options '("a" "b"))))))))
    (testing "contents that do not fit are counted in the description and listed in the object"
      (let ((change (append (only (diff-schemas (blog) (blog :required t)))
                            (list :misfits (list (list :id "a" :field "title" :version "draft" :message "is required")
                                                 (list :id "a" :field "title" :version "published" :message "is required")
                                                 (list :id "b" :field "title" :version "draft" :message "is required"))))))
        (ok (search "2 contents do not fit" (format-change change)))
        (let ((misfits (jget (change->jobject change) "misfits")))
          (ok (= (length misfits) 3))
          (ok (equal (jget (aref misfits 0) "id") "a"))
          (ok (equal (jget (aref misfits 0) "version") "draft"))
          (ok (equal (jget (aref misfits 0) "message") "is required")))
        (ng (jget (change->jobject (only (diff-schemas (blog) (blog :required t)))) "misfits")
            "and a change with none has no list")))))

(deftest renames
  (flet ((posts (&rest fields)
           (make-schema :models (list (make-model "post" :list fields))))
         (articles (&rest fields)
           (make-schema :models (list (make-model "article" :list fields :was 'post)))))
    (testing "a field named by :was is renamed, not removed and added"
      (let ((changes (diff-schemas (posts (make-field :lede :text))
                                   (posts (make-field :subtitle :text :was :lede)))))
        (ok (equal (ops changes) '(:rename-field)))
        (ng (destructive-changes-p changes) "nothing is lost, so no force is needed")
        (ok (string= (getf (first changes) :from) "lede"))
        (ok (string= (getf (first changes) :field) "subtitle"))
        (ok (search "post.subtitle renamed from lede" (format-change (first changes))))
        (ok (string= (jget (change->jobject (first changes)) "op") "rename_field"))
        (ok (string= (jget (change->jobject (first changes)) "path") "post.subtitle"))))
    (testing "without :was the same edit throws the content away"
      (ok (equal (ops (diff-schemas (posts (make-field :lede :text))
                                    (posts (make-field :subtitle :text))))
                 '(:remove-field :add-field))))
    (testing "a renamed field is still compared"
      (let ((changes (diff-schemas (posts (make-field :lede :text))
                                   (posts (make-field :subtitle :text :required t :was :lede)))))
        (ok (equal (ops changes) '(:rename-field :change-field-options)))
        (ok (tightened-change-p (second changes)) "the rename is free, the new constraint is checked")))
    (testing "a leftover :was is not a change"
      (ok (null (diff-schemas (posts (make-field :subtitle :text))
                              (posts (make-field :subtitle :text :was :lede))))
          "the annotation stays in the source after the deploy that consumed it"))
    (testing "an ambiguous :was renames nothing"
      (ok (equal (ops (diff-schemas (posts (make-field :lede :text) (make-field :subtitle :text))
                                    (posts (make-field :subtitle :text :was :lede))))
                 '(:remove-field))
          "the new name is already taken in the deployed schema, so this drops a field"))
    (testing "a model is renamed the same way"
      (let ((changes (diff-schemas (posts (make-field :title :text))
                                   (articles (make-field :title :text)))))
        (ok (equal (ops changes) '(:rename-model)))
        (ng (destructive-changes-p changes))
        (ok (search "article renamed from post" (format-change (first changes))))
        (ok (string= (jget (change->jobject (first changes)) "op") "rename_model")))
      (let ((changes (diff-schemas (posts (make-field :lede :text))
                                   (articles (make-field :subtitle :text :was :lede)))))
        (ok (equal (ops changes) '(:rename-model :rename-field))
            "the model moves first, so the field rename names it by its new name")
        (ok (string= (getf (second changes) :model) "article"))))))

(deftest webhooks
  (flet ((with-hooks (&rest hooks)
           (make-schema :webhooks hooks :models (list (make-model "blog" :list (list (make-field :title :text)))))))
    (let ((changes (diff-schemas (with-hooks) (with-hooks (make-webhook "preview" "https://p")))))
      (ok (equal (ops changes) '(:change-webhooks)))
      (ng (destructive-changes-p changes))
      (ok (search "webhooks changed" (format-change (first changes)))))
    (ok (null (diff-schemas (with-hooks (make-webhook "a" "https://a"))
                            (with-hooks (make-webhook "a" "https://a"))))
        "same hook: no change")
    (ok (equal (ops (diff-schemas (with-hooks (make-webhook "a" "https://a"))
                                  (with-hooks (make-webhook "a" "https://a" :only '(blog)))))
               '(:change-webhooks))
        "narrowing an existing hook with :only is a change")))

(deftest from-nothing
  (let ((changes (diff-schemas nil (schema-a))))
    (ok (equal (ops changes) '(:add-model :add-field :add-field :add-model :add-field))
        "an empty space is the same as no space at all")
    (ng (destructive-changes-p changes))))

(deftest full-diff
  (let ((changes (diff-schemas (schema-a) (schema-b))))
    (ok (equal (ops changes)
               '(:change-webhooks
                 :remove-model
                 :change-field-options :change-field-type :add-field
                 :add-model :add-field)))
    (ok (destructive-changes-p changes))
    (let ((type-change (find :change-field-type changes :key (lambda (c) (getf c :op)))))
      (ok (string= (getf type-change :field) "body"))
      (ok (eq (getf type-change :from) :richtext))
      (ok (eq (getf type-change :to) :textarea))
      (ok (search "richtext -> textarea" (format-change type-change)))
      (ok (jget (change->jobject type-change) "destructive"))
      (ok (string= (jget (change->jobject type-change) "op") "change_field_type"))
      (ok (string= (jget (change->jobject type-change) "path") "blog.body")))
    (ok (search "- about" (format-change (second changes))))
    (ok (string= (string-trim " " (format-change (first changes))) "~ webhooks changed")
        "the space's own webhooks are named by the path, not by a space")))

(deftest a-change-of-kind-says-the-contents-go
  (flet ((about (kind) (make-schema :models (list (make-model "about" kind (list (make-field :body :richtext)))))))
    (let ((changes (diff-schemas (about :list) (about :object))))
      (ok (equal (ops changes) '(:change-kind)))
      (ok (destructive-changes-p changes))
      (ok (search "list -> object, its contents are deleted" (format-change (first changes)))))
    (ok (search "object -> list, its contents are deleted"
                (format-change (first (diff-schemas (about :object) (about :list)))))
        "either way")))

(deftest field-help
  (flet ((blog (&rest cover-options)
           (make-schema :models (list (make-model "blog" :list
                                                  (list (apply #'make-field :cover :media cover-options)))))))
    (let ((changes (diff-schemas (blog) (blog :help "1200x630"))))
      (ok (equal (ops changes) '(:change-field-options)) "a help text is an option of its field")
      (ng (destructive-changes-p changes))
      (ng (tightened-change-p (first changes)) "and no content stops fitting for it"))))

(defun with-custom (seo-fields &key (used t) (name "seo"))
  (make-schema :custom-fields (list (make-custom-field name seo-fields))
               :models (list (make-model "blog" :list
                                         (append (list (make-field :title :text))
                                                 (and used (list (make-field :meta :custom :custom-field name)))))
                             (make-model "page" :list
                                         (and used (list (make-field :meta :custom :custom-field name)))))))

(defun seo-fields (&rest more)
  (append (list (make-field :title :text)) more))

(deftest custom-fields
  (testing "a definition changes on its own, so a deploy keeps it even where nothing uses it"
    (let ((changes (diff-schemas (with-custom (seo-fields) :used nil)
                                 (with-custom (seo-fields (make-field :image :media)) :used nil))))
      (ok (equal (ops changes) '(:change-custom-fields)))
      (ng (destructive-changes-p changes))
      (ok (search "customFields changed" (format-change (first changes))))))
  (testing "a field added inside is added in every model that uses it"
    (let ((changes (remove :change-custom-fields
                           (diff-schemas (with-custom (seo-fields)) (with-custom (seo-fields (make-field :image :media))))
                           :key (lambda (c) (getf c :op)))))
      (ok (equal (mapcar (lambda (c) (list (getf c :op) (getf c :model) (getf c :field))) changes)
                 '((:add-field "blog" "meta.image") (:add-field "page" "meta.image"))))
      (ng (destructive-changes-p changes))
      (ok (search "blog.meta.image (media)" (format-change (first changes))))))
  (testing "removing or retyping one inside is destructive, there"
    (let ((removed (diff-schemas (with-custom (seo-fields (make-field :image :media))) (with-custom (seo-fields)))))
      (ok (member :remove-field (ops removed)))
      (ok (destructive-changes-p removed)))
    (let ((retyped (diff-schemas (with-custom (seo-fields)) (with-custom (list (make-field :title :textarea))))))
      (ok (equal (remove :change-custom-fields (ops retyped)) '(:change-field-type :change-field-type)))
      (ok (destructive-changes-p retyped))))
  (testing "tightening one inside is tightening"
    (let ((change (find :change-field-options
                        (diff-schemas (with-custom (seo-fields)) (with-custom (list (make-field :title :text :required t))))
                        :key (lambda (c) (getf c :op)))))
      (ok (string= (getf change :field) "meta.title"))
      (ok (tightened-change-p change))))
  (testing "a field pointed at another custom field holds values of another type"
    (let* ((two (lambda (target)
                  (make-schema :custom-fields (list (make-custom-field "seo" (seo-fields))
                                                    (make-custom-field "card" (seo-fields)))
                               :models (list (make-model "blog" :list
                                                         (list (make-field :meta :custom :custom-field target)))))))
           (changes (diff-schemas (funcall two "seo") (funcall two "card"))))
      (ok (equal (ops changes) '(:change-field-type)))
      (ok (destructive-changes-p changes))))
  (testing "nothing changed is no change"
    (ng (diff-schemas (with-custom (seo-fields)) (with-custom (seo-fields))))))
