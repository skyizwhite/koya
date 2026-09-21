(defpackage #:koya-tests/core/diff
  (:use #:cl #:rove)
  (:import-from #:koya/core/schema
                #:make-field #:make-model #:make-space #:make-schema #:make-webhook)
  (:import-from #:koya/core/diff
                #:diff-schemas
                #:destructive-changes-p
                #:format-change
                #:change->jobject)
  (:import-from #:koya/core/json
                #:jget))
(in-package #:koya-tests/core/diff)

(defun schema-a ()
  (make-schema (list (make-space "website"
                                 :models (list (make-model "blog" :list
                                                           (list (make-field :title :text :required t)
                                                                 (make-field :body :richtext)))
                                               (make-model "about" :object (list (make-field :body :richtext))))))))

(defun schema-b ()
  (make-schema (list (make-space "website"
                                 :webhooks (list (make-webhook "x" "https://x" :events '(:publish :unpublish :delete)))
                                 :models (list (make-model "blog" :list
                                                           (list (make-field :title :text :required t :max-length 50)
                                                                 (make-field :body :textarea)
                                                                 (make-field :event-at :datetime)))
                                               (make-model "tag" :list (list (make-field :name :text)))))
                     (make-space "other"))))

(defun ops (changes) (mapcar (lambda (c) (getf c :op)) changes))

(deftest no-changes
  (ok (null (diff-schemas (schema-a) (schema-a)))))

(deftest model-options
  (let* ((with-url (make-schema (list (make-space "website"
                                                  :models (list (make-model "blog" :list (list (make-field :title :text :required t)
                                                                                               (make-field :body :richtext))
                                                                            :public-url "https://x/blog/{CONTENT_ID}")
                                                                (make-model "about" :object (list (make-field :body :richtext))))))))
         (changes (diff-schemas (schema-a) with-url)))
    (ok (equal (ops changes) '(:change-model-options)))
    (ng (destructive-changes-p changes))
    (ok (search "options changed" (format-change (first changes))))))

(deftest field-options
  (flet ((blog (&rest title-options)
           (make-schema (list (make-space "website"
                                          :models (list (make-model "blog" :list
                                                                    (list (apply #'make-field :title :text title-options))))))))
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
               (make-schema (list (make-space "website"
                                              :models (list (make-model "blog" :list
                                                                        (list (apply #'make-field :cat :select options)))))))))
        (ok (destructive-changes-p (diff-schemas (sel :options '("a" "b") :many t) (sel :options '("a" "b")))))
        (ok (destructive-changes-p (diff-schemas (sel :options '("a" "b")) (sel :options '("a")))))
        (ng (destructive-changes-p (diff-schemas (sel :options '("a")) (sel :options '("a" "b")))))))))

(deftest model-webhooks
  (flet ((blog (&rest hooks)
           (make-schema (list (make-space "website"
                                          :models (list (make-model "blog" :list (list (make-field :title :text))
                                                                    :webhooks hooks)))))))
    (let ((changes (diff-schemas (blog) (blog (make-webhook "preview" "https://p" :events '(:draft))))))
      (ok (equal (ops changes) '(:change-model-webhooks)))
      (ng (destructive-changes-p changes))
      (ok (search "webhooks changed" (format-change (first changes)))))
    (ok (null (diff-schemas (blog (make-webhook "a" "https://a" :events '(:publish :draft)))
                            (blog (make-webhook "a" "https://a" :events '("draft" :publish :publish)))))
        "same hook, different spelling: no change")))

(deftest from-nothing
  (let ((changes (diff-schemas nil (schema-a))))
    (ok (equal (ops changes) '(:add-space :add-model :add-field :add-field :add-model :add-field)))
    (ng (destructive-changes-p changes))))

(deftest full-diff
  (let ((changes (diff-schemas (schema-a) (schema-b))))
    (ok (equal (ops changes)
               '(:change-webhooks
                 :remove-model
                 :change-field-options :change-field-type :add-field
                 :add-model :add-field
                 :add-space)))
    (ok (destructive-changes-p changes))
    (let ((type-change (find :change-field-type changes :key (lambda (c) (getf c :op)))))
      (ok (string= (getf type-change :field) "body"))
      (ok (eq (getf type-change :from) :richtext))
      (ok (eq (getf type-change :to) :textarea))
      (ok (search "richtext -> textarea" (format-change type-change)))
      (ok (jget (change->jobject type-change) "destructive"))
      (ok (string= (jget (change->jobject type-change) "op") "change_field_type"))
      (ok (string= (jget (change->jobject type-change) "path") "website.blog.body")))
    (ok (search "- website.about" (format-change (second changes))))
    (ok (string= (string-trim " " (format-change (first (diff-schemas nil (schema-a))))) "+ website"))))
