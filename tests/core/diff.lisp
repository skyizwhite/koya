(defpackage #:koya-tests/core/diff
  (:use #:cl #:rove)
  (:import-from #:koya/core/schema
                #:make-field #:make-model #:make-space #:make-schema)
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
                                 :webhooks '("https://x")
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
