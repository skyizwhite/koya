(defpackage #:koya-server/components/field-input
  (:use #:cl #:hsx)
  (:import-from #:koya/core/schema
                #:field-name #:field-type #:field-option #:field-required-p #:field-many-p)
  (:import-from #:koya/core/json
                #:json-null)
  (:import-from #:koya-server/lib/forms
                #:field-param-name #:value->string)
  (:export #:~field-input))
(in-package #:koya-server/components/field-input)

;;; One form control per field type.

(defun present-p (value) (and value (not (eq value json-null))))

(defun selected-p (value option)
  (if (present-p value)
      (if (and (vectorp value) (not (stringp value)))
          (and (find option value :test #'equal) t)
          (equal option value))
      nil))

(defun reference-choices (value references)
  "REFERENCES as (id . label), plus any selected id it lacks so nothing is dropped silently."
  (let ((selected (cond ((not (present-p value)) '())
                        ((and (vectorp value) (not (stringp value))) (coerce value 'list))
                        (t (list value)))))
    (append references
            (loop :for id :in selected
                  :unless (assoc id references :test #'equal)
                    :collect (cons id (format nil "~a (missing)" id))))))

(defcomp ~reference-select (&key field value references)
  (let* ((name (field-param-name field))
         (choices (reference-choices value references))
         (many (field-many-p field)))
    (hsx
     (<>
       ;; a many-reference is enhanced into chips + a dropdown by koya-editor.js
       (select :id name :name name :multiple many :data-picker many
         (if many (hsx (<>)) (hsx (option :value "" "—")))
         (loop :for (id . label) :in choices :collect
           (hsx (option :value id :selected (selected-p value id) label))))
       (p :class "text-xs text-muted"
         (format nil "~a content~:p of ~a" (length choices) (field-option field :model)))))))

(defcomp ~field-input (&key field value error references)
  (let* ((name (field-param-name field))
         (id name)
         (type (field-type field))
         (string (value->string field value)))
    (hsx
     (div :class "space-y-1.5"
       (label :for id :class "label"
         (field-name field)
         (span :class "ml-2 text-xs font-normal text-muted" (string-downcase (symbol-name type)))
         (when (field-required-p field) (hsx (span :class "ml-1 text-danger" "*"))))
       (case type
         ((:text :slug)
          (hsx (input :type "text" :id id :name name :value string :class "input")))
         (:textarea
          (hsx (textarea :id id :name name :rows 5 :class "input" string)))
         (:richtext
          (hsx
           (<>
             (input :type "hidden" :id id :name name :value string)
             (div :class "quill-editor" :data-quill-for id))))
         (:number
          (hsx (input :type "number" :id id :name name :value string :step "any" :class "input")))
         (:boolean
          (hsx (label :class "inline-flex items-center gap-2 text-sm"
                 (input :type "checkbox" :id id :name name :checked (eq value t))
                 "true")))
         (:date
          (hsx (input :type "date" :id id :name name :value string :class "input")))
         (:datetime
          (hsx (<> (input :type "datetime-local" :id id :name name :value string :class "input")
                   (p :class "text-xs text-muted" "UTC"))))
         (:select
          (if (field-many-p field)
              (hsx (div :class "flex flex-wrap gap-3"
                     (loop :for option :in (field-option field :options) :collect
                       (hsx (label :class "inline-flex items-center gap-1.5 text-sm"
                              (input :type "checkbox" :name name :value option
                                     :checked (and (present-p value) (find option value :test #'equal) t))
                              option)))))
              (hsx (select :id id :name name
                     (option :value "" "—")
                     (loop :for option :in (field-option field :options) :collect
                       (hsx (option :value option :selected (equal option value) option)))))))
         (:reference
          (hsx (~reference-select :field field :value value :references references)))
         (:media
          (hsx (<> (input :type "text" :id id :name name :value string :class "input font-mono text-xs"
                          :placeholder (if (field-many-p field) "id, id, ..." "id"))
                   (p :class "text-xs text-muted" "media id"))))
         (t (hsx (input :type "text" :id id :name name :value string :class "input"))))
       (if error
           (hsx (p :class "text-xs text-danger" error))
           (hsx (<>)))))))
