(defpackage #:koya-server/web/ui/content/reference-picker
  (:use #:cl #:hsx)
  (:import-from #:ningle-actions #:defaction)
  (:import-from #:jingle #:set-response-status)
  (:import-from #:koya-server/web/lib/binds #:js-string #:on-search #:on-reveal)
  (:import-from #:koya-server/web/lib/http #:param)
  (:import-from #:koya-server/web/lib/paging #:page-number)
  (:import-from #:koya-server/web/lib/urls #:editor-url)
  (:import-from #:koya-core/schema #:model-name)
  (:import-from #:koya-server/usecases/schema #:find-model)
  (:import-from #:koya-server/usecases/listing #:content-page)
  (:import-from #:koya-server/domain/content #:content-id #:content-label #:content-status)
  (:import-from #:koya-server/web/ui/elements #:~status-badge #:~empty-state)
  (:import-from #:koya-server/web/ui/icon #:~icon)
  (:import-from #:koya-server/web/ui/content/field-input #:~reference-card)
  (:export #:reference-picker
           #:reference-picker-search
           #:reference-picker-more
           #:~reference-picker-dialog))
(in-package #:koya-server/web/ui/content/reference-picker)

(defparameter +picker-size+ 20)

(defun picker-items (space model many search page)
  (multiple-value-bind (contents total pages)
      (content-page space model :page page :page-size +picker-size+ :search-text search)
    (declare (ignore total))
    (values contents
            (and (< page pages)
                 (reference-picker-more :space space :model (model-name model)
                                        :many many :q (or search "") :page (1+ page))))))

(defcomp ~pick-item (&key space model content many)
  (let ((id (content-id content))
        (label (content-label content model)))
    (hsx
     (li
       (button :type "button"
               :class "flex w-full items-center gap-2 rounded-md px-3 py-2 text-left text-sm ring-accent hover:bg-accent/5 disabled:opacity-50"
               :data-pick-id id
               :nm-bind "{ onclick: () => _pick(this.dataset.pickId), 'class.ring-2': () => _has(this.dataset.pickId), disabled: () => _taken(this.dataset.pickId), ariaPressed: () => _many ? String(_has(this.dataset.pickId)) : null }"
         (span :class "min-w-0 flex-1 truncate" label)
         (~status-badge :status (content-status content)))
       (template
         (~reference-card :name "" :many many :id id :label label :status (content-status content)
                          :href (editor-url space model id)))))))

(defcomp ~pick-items (&key space model items many more)
  (hsx
   (<> (loop :for content :in items :collect
         (hsx (~pick-item :space space :model model :content content :many many)))
       (when more
         (hsx (li :id more :class "py-2 text-center text-xs text-muted" :nm-bind (on-reveal more)
                "Loading…"))))))

(defcomp ~pick-list (&key space model many search)
  (multiple-value-bind (items more) (picker-items space model (if many "true" "false") search 1)
    (hsx
     (div :id "reference-picker-list"
       (if items
           (hsx (ul :class "space-y-1"
                  (~pick-items :space space :model model :items items :many many :more more)))
           (hsx (~empty-state "No contents.")))))))

(defcomp ~picker-body (&key space model many search)
  (let ((model-name (model-name model)))
    (hsx
     (div :id "reference-picker-body" :class "space-y-4"
       (form :nm-data "...koya.search()" :class "flex gap-2"
             :nm-bind (on-search (reference-picker-search :space space :model model-name :many (if many "true" "false")))
         (input :type "search" :name "q" :value (or search "") :placeholder (format nil "Search ~a" model-name)
                :class "input" :aria-label "Search"))
       (~pick-list :space space :model model :many many :search search)))))

(defun picker-target (params)
  (let ((space (param params "space"))
        (name (param params "model")))
    (and space name (find-model space name))))

(defun unknown ()
  (set-response-status 404)
  (hsx (div :id "reference-picker-body" :class "text-sm text-danger" "Unknown model.")))

(defun many-p (params)
  (equal (param params "many") "true"))

(defaction reference-picker :get (params)
  (let ((model (picker-target params)))
    (if model
        (hsx (~picker-body :space (param params "space") :model model :many (many-p params) :search (param params "q")))
        (unknown))))

(defaction reference-picker-search :get (params)
  (let ((model (picker-target params)))
    (if model
        (hsx (~pick-list :space (param params "space") :model model :many (many-p params) :search (param params "q")))
        (unknown))))

(defaction reference-picker-more :get (params)
  (let ((model (picker-target params))
        (space (param params "space")))
    (if model
        (let ((many (if (many-p params) "true" "false")))
          (multiple-value-bind (items more) (picker-items space model many (param params "q") (page-number params))
            (let ((asked (reference-picker-more :space space :model (param params "model") :many many
                                                :q (or (param params "q") "") :page (page-number params))))
              (hsx (<> (ul :id asked :nm-swap "before"
                         (~pick-items :space space :model model :items items :many (many-p params) :more more))
                       (li :id asked :hidden t))))))
        (unknown))))

(defcomp ~reference-picker-dialog (&key space)
  (hsx
   (dialog :id "reference-picker" :class "koya-dialog koya-dialog-wide max-w-xl"
           :nm-data (format nil "...koya.referencePicker(this, ~a)" (js-string (reference-picker :space space)))
           :nm-bind "{ onclick: (e) => e.target === this && _close(), onopenpicker: (e) => _open(e.detail) }"
     (div :class "flex items-center justify-between border-b border-line px-4 py-3"
       (h2 :class "font-semibold" "Contents")
       (button :type "button" :class "btn btn-icon" :nm-bind "{ onclick: () => _close() }" :aria-label "Close"
         (~icon :name :close)))
     (div :class "max-h-[70vh] overflow-y-auto p-4"
       (div :id "reference-picker-body" :class "text-sm text-muted" "Loading…"))
     (div :class "flex items-center justify-end gap-3 border-t border-line px-4 py-3" :hidden t
          :nm-bind "{ hidden: () => !_many }"
       (span :class "text-sm text-muted" :nm-bind "{ textContent: () => `${_chosen.length} chosen` }")
       (button :type "button" :class "btn btn-primary"
               :nm-bind "{ onclick: () => _done(), disabled: () => !_chosen.length }"
         (~icon :name :check) "Add")))))
