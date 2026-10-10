(defpackage #:koya-server/web/ui/content/field-input
  (:use #:cl #:hsx)
  (:import-from #:koya-core/schema
                #:field-name #:field-type #:field-option #:field-required-p #:field-many-p
                #:field-row-kinds #:custom-field-name)
  (:import-from #:koya-core/json
                #:json-null #:to-json #:jobject #:json-array-p #:blank-p)
  (:import-from #:koya-server/web/lib/forms #:field-param-name #:value->string)
  (:import-from #:koya-server/domain/media #:media-filename #:media-alt)
  (:import-from #:koya-server/web/lib/presenters #:media-url)
  (:import-from #:koya-server/usecases/settings #:display-timezone-name)
  (:import-from #:koya-server/web/ui/icon #:~icon)
  (:import-from #:koya-server/web/lib/binds #:js-string)
  (:export #:~field-input #:~custom-input #:~repeater-input))
(in-package #:koya-server/web/ui/content/field-input)

(defun present-p (value) (and value (not (eq value json-null))))

(defun selected-p (value option)
  (if (present-p value)
      (if (json-array-p value)
          (and (find option value :test #'equal) t)
          (equal option value))
      nil))

(defun reference-choices (value references)
  (let ((selected (cond ((not (present-p value)) '())
                        ((json-array-p value) (coerce value 'list))
                        (t (list value)))))
    (append references
            (loop :for id :in selected
                  :unless (assoc id references :test #'equal)
                    :collect (cons id (format nil "~a (missing)" id))))))

(defcomp ~reference-chips (&key name value choices)
  (hsx
   (div :class "flex flex-wrap items-center gap-2" :nm-data "...koya.references(this)"
     (select :id name :name name :multiple t :hidden t :nm-ref "select"
       (loop :for (id . label) :in choices :collect
         (hsx (option :value id :selected (selected-p value id)
                      :nm-bind "{ selected: () => _has(this.value) }"
                label))))
     (loop :for (id . label) :in choices :collect
       (hsx (span :class "badge inline-flex items-center gap-1 bg-line text-fg"
                  :data-id id :hidden (not (selected-p value id))
                  :nm-bind "{ hidden: () => !_has(this.dataset.id) }"
              label
              (button :type "button" :class "text-muted hover:text-danger" :data-id id
                      :aria-label (format nil "Remove ~a" label)
                      :nm-bind "{ onclick: () => _remove(this.dataset.id) }"
                "×"))))
     (select :aria-label "Add" :nm-bind "{ onchange: () => _add(this) }"
       (option :value "" "Add…")
       (loop :for (id . label) :in choices :collect
         (let ((chosen (selected-p value id)))
           (hsx (option :value id :hidden chosen :disabled chosen
                        :nm-bind "{ hidden: () => _has(this.value), disabled: () => _has(this.value) }"
                  label))))))))

(defcomp ~reference-select (&key field parent value references)
  (let ((name (field-param-name field parent))
        (choices (reference-choices value references)))
    (hsx
     (<>
       (if (field-many-p field)
           (hsx (~reference-chips :name name :value value :choices choices))
           (hsx (select :id name :name name
                  (option :value "" "—")
                  (loop :for (id . label) :in choices :collect
                    (hsx (option :value id :selected (selected-p value id) label))))))
       (p :class "text-xs text-muted"
         (format nil "~a content~:p of ~a" (length choices) (field-option field :model)))))))

(defcomp ~media-control (&key name value media)
  (let ((url (if media (media-url media :absolute nil) ""))
        (alt (if media (media-alt media) ""))
        (label (cond (media (media-filename media))
                     ((not (blank-p value)) (format nil "~a (missing)" value))
                     (t "No image"))))
    (hsx
     (div :class "flex items-start gap-4"
          :nm-data (format nil "...koya.mediaField(~a)"
                           (to-json (jobject "id" (or value "") "url" url "alt" alt "name" label)))
       (input :type "hidden" :id name :name name :value (or value "") :nm-ref "input"
              :nm-bind "{ value: () => _id }")
       (img :src url :alt alt
            :class (clsx "h-24 w-24 rounded-md border border-line bg-panel object-contain" (unless media "hidden"))
            :nm-bind "{ src: () => _url, alt: () => _alt, 'class.hidden': () => !_url }")
       (div :class "space-y-2 text-sm"
         (div :class "text-muted" :nm-bind "{ textContent: () => _name }" label)
         (div :class "flex gap-2"
           (button :type "button" :class "btn" :nm-bind "{ onclick: () => _choose() }"
             (~icon :name :media) "Choose…")
           (button :type "button" :class "btn" :nm-bind "{ onclick: () => _clear() }"
             (~icon :name :close) "Clear")))))))

(defcomp ~media-entry (&key name id media)
  (hsx
   (li :class "w-28 space-y-1" :data-row t
     (img :src (if media (media-url media :absolute nil) "") :alt (if media (media-alt media) "")
          :data-drag-handle t :draggable "false"
          :class "h-28 w-28 cursor-move rounded-md border border-line bg-panel object-contain")
     (div :class "truncate text-xs text-muted" :data-media-name t
          :title (cond (media (media-filename media)) (id (format nil "~a (missing)" id)) (t ""))
       (cond (media (media-filename media)) (id (format nil "~a (missing)" id)) (t "")))
     (div :class "flex gap-1"
       (button :type "button" :class "btn btn-icon py-1" :aria-label "Move image left" :data-action "left"
         (~icon :name :prev))
       (button :type "button" :class "btn btn-icon py-1" :aria-label "Move image right" :data-action "right"
         (~icon :name :next))
       (button :type "button" :class "btn btn-icon py-1" :aria-label "Remove image" :data-action "remove"
         (~icon :name :close)))
     (input :type "hidden" :name name :value (or id "")))))

(defcomp ~media-list-control (&key name entries)
  (hsx
   (div :class "space-y-2" :nm-data "...koya.mediaList(this)"
     (ul :id name :class "flex flex-wrap gap-3 empty:hidden" :data-media-list t :data-sort-axis "x"
         :nm-bind "{ oninit: () => koya.sortable(this) }"
       (loop :for (id . media) :in entries :collect (hsx (~media-entry :name name :id id :media media))))
     (template (~media-entry :name name))
     (button :type "button" :class "btn" :nm-bind "{ onclick: () => _add() }"
       (~icon :name :media) "Add images"))))

(defcomp ~field-error (&key field parent error)
  (hsx (p :id (format nil "~a-error" (field-param-name field parent)) :class "text-xs text-danger" :hidden (null error) error)))

(defcomp ~custom-input (&key field present error children)
  (let* ((name (field-param-name field))
         (required (field-required-p field))
         (on (or required present)))
    (hsx
     (div :class "space-y-1.5" :nm-data (format nil "...koya.customField(~:[false~;true~])" on)
       (div :class "flex items-center justify-between gap-3"
         (div :id (format nil "~a-label" name) :class "label"
           (field-name field)
           (span :class "ml-2 text-xs font-normal text-muted" "custom")
           (when required (hsx (span :class "ml-1 text-danger" "*")))
           (when (field-option field :help)
             (hsx (span :id (format nil "~a-help" name) :class "ml-3 text-xs font-normal text-muted"
                    (field-option field :help)))))
         (unless required
           (hsx (button :type "button" :class "btn" :hidden (not on)
                        :nm-bind "{ hidden: () => !_on, onclick: () => _remove() }"
                  (~icon :name :close) (format nil "Remove ~a" (field-name field))))))
       (input :type "hidden" :name name :value "on" :disabled (not on) :nm-ref "marker"
              :nm-bind "{ disabled: () => !_on }")
       (unless required
         (hsx (div :class "rounded-md border border-dashed border-line p-4" :hidden on
                   :nm-bind "{ hidden: () => _on }"
                (button :type "button" :class "btn" :nm-bind "{ onclick: () => _add() }"
                  (~icon :name :plus) (format nil "Add ~a" (field-name field))))))
       (fieldset :id name :aria-labelledby (format nil "~a-label" name)
                 :class "space-y-4 rounded-md border border-line p-4"
                 :hidden (not on) :disabled (not on)
                 :nm-bind "{ hidden: () => !_on, disabled: () => !_on }"
         children)
       (~field-error :field field :error error)))))

(defcomp ~repeater-input (&key field add-url error children)
  (let ((name (field-param-name field)))
    (hsx
     (div :class "space-y-1.5" :nm-data (format nil "...koya.repeater(~a)" (js-string add-url))
       (div :id (format nil "~a-label" name) :class "label"
         (field-name field)
         (span :class "ml-2 text-xs font-normal text-muted" "repeater")
         (when (field-required-p field) (hsx (span :class "ml-1 text-danger" "*")))
         (when (field-option field :help)
           (hsx (span :id (format nil "~a-help" name) :class "ml-3 text-xs font-normal text-muted"
                  (field-option field :help)))))
       (div :class "space-y-3 rounded-md border border-line p-4"
         (div :id (format nil "~a-rows" name) :class "space-y-3 empty:hidden" :role "list" :aria-labelledby (format nil "~a-label" name)
              :nm-bind "{ oninit: () => koya.sortable(this) }"
           children)
         (div :class "flex items-center gap-2"
           (select :aria-label (format nil "Custom field of a new ~a row" (field-name field)) :nm-ref "kind" :class "w-auto"
             (loop :for kind :in (field-row-kinds field) :collect
               (hsx (option :value (custom-field-name kind) (custom-field-name kind)))))
           (button :type "button" :class "btn" :nm-bind "{ onclick: () => _add($refs.kind) }"
             (~icon :name :plus) "Add row")))
       (~field-error :field field :error error)))))

(defcomp ~field-input (&key field parent value error references media)
  (let* ((name (field-param-name field parent))
         (id name)
         (type (field-type field))
         (string (value->string field value)))
    (hsx
     (div :class "space-y-1.5"
       (label :for id :class "label"
         (field-name field)
         (span :class "ml-2 text-xs font-normal text-muted" (string-downcase (symbol-name type)))
         (when (field-required-p field) (hsx (span :class "ml-1 text-danger" "*"))))
       (when (field-option field :help)
         (hsx (p :id (format nil "~a-help" name) :class "text-xs text-muted" (field-option field :help))))
       (case type
         ((:text :slug)
          (hsx (input :type "text" :id id :name name :value string :class "input")))
         (:textarea
          (hsx (textarea :id id :name name :rows 5 :class "input" string)))
         (:richtext
          (hsx
           (div
             (input :type "hidden" :id id :name name :value string)
             (div :class "quill-editor" :data-quill-for id
                  :nm-bind "{ oninit: () => koya.quill(this) }"))))
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
                   (p :class "text-xs text-muted" (display-timezone-name)))))
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
          (hsx (~reference-select :field field :parent parent :value value :references references)))
         (:media
          (if (field-many-p field)
              (hsx (~media-list-control :name name
                                        :entries (and (present-p value) (json-array-p value)
                                                      (map 'list (lambda (id) (cons id (cdr (assoc id media :test #'equal)))) value))))
              (hsx (~media-control :name name :value (and (present-p value) (stringp value) value) :media media))))
         (t (hsx (input :type "text" :id id :name name :value string :class "input"))))
       (~field-error :field field :parent parent :error error)))))
