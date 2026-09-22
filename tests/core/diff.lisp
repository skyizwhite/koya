(defpackage #:koya-tests/core/diff
  (:use #:cl #:rove)
  (:import-from #:koya/core/schema
                #:make-field #:make-model #:make-schema #:make-webhook)
  (:import-from #:koya/core/diff
                #:diff-schemas
                #:destructive-changes-p
                #:format-change
                #:change->jobject)
  (:import-from #:koya/core/json
                #:jget))
(in-package #:koya-tests/core/diff)

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

(deftest field-options
  (flet ((blog (&rest title-options)
           (make-schema :models (list (make-model "blog" :list
                                                  (list (apply #'make-field :title :text title-options))))))
         (only (changes) (progn (ok (= (length changes) 1)) (first changes))))
    (testing "case-only changes are seen"
      (let ((change (only (diff-schemas (blog :pattern "^[A-Z]") (blog :pattern "^[a-z]")))))
        (ok (eq (getf change :op) :change-field-options))
        (ok (destructive-changes-p (list change)) "a different pattern can reject existing content")))
    (testing "loosening is not destructive"
      (ng (destructive-changes-p (diff-schemas (blog :max-length 50) (blog :max-length 100))))
      (ng (destructive-changes-p (diff-schemas (blog :required t) (blog)))))
    (testing "tightening is destructive"
      (ok (destructive-changes-p (diff-schemas (blog) (blog :required t))))
      (ok (destructive-changes-p (diff-schemas (blog :max-length 100) (blog :max-length 50))))
      (ok (destructive-changes-p (diff-schemas (blog) (blog :unique t))))
      (ok (search "options tightened" (format-change (only (diff-schemas (blog) (blog :required t)))))))
    (testing "changing single/many and dropping select options is destructive"
      (flet ((sel (&rest options)
               (make-schema :models (list (make-model "blog" :list
                                                      (list (apply #'make-field :cat :select options)))))))
        (ok (destructive-changes-p (diff-schemas (sel :options '("a" "b") :many t) (sel :options '("a" "b")))))
        (ok (destructive-changes-p (diff-schemas (sel :options '("a" "b")) (sel :options '("a")))))
        (ng (destructive-changes-p (diff-schemas (sel :options '("a")) (sel :options '("a" "b")))))))))

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
        (ok (destructive-changes-p changes) "the rename is free, the new constraint is not")))
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
