(defpackage #:koya-sdk/config
  (:use #:cl)
  (:import-from #:koya-core/schema
                #:make-field
                #:make-model
                #:make-custom-field
                #:custom-field-name
                #:make-webhook
                #:make-schema
                #:check-schema
                #:model-name
                #:model-was)
  (:export #:defwebhooks
           #:defmodel
           #:defcustomfield
           #:webhook
           #:current-schema
           #:clear-schema
           #:find-model))
(in-package #:koya-sdk/config)

(defvar *webhooks* '())

(defvar *models* '())

(defvar *custom-fields* '())

(defun clear-schema ()
  "Forget every model, custom field and webhook defined so far."
  (setf *webhooks* '()
        *models* '()
        *custom-fields* '()))

(defun model-key (name) (string-downcase (string name)))

(defun find-model (name)
  "The model defined as NAME, or NIL."
  (cdr (assoc (model-key name) *models* :test #'string=)))

(defun register-webhooks (webhooks)
  (make-schema :webhooks webhooks)
  (setf *webhooks* webhooks))

(defun register-model (model)
  (let* ((key (model-name model))
         (was (model-was model))
         (entry (assoc key *models* :test #'string=)))
    (when was
      (setf *models* (remove was *models* :key #'car :test #'string=)))
    (if entry
        (setf (cdr entry) model)
        (setf *models* (append *models* (list (cons key model)))))
    model))

(defun register-custom-field (custom)
  (let* ((key (custom-field-name custom))
         (entry (assoc key *custom-fields* :test #'string=)))
    (if entry
        (setf (cdr entry) custom)
        (setf *custom-fields* (append *custom-fields* (list (cons key custom)))))
    custom))

(eval-when (:compile-toplevel :load-toplevel :execute)
  (defun field-forms (fields)
    `(list ,@(loop :for (fname ftype . options) :in fields
                   :collect `(make-field ',fname ,ftype
                                         ,@(loop :for (k v) :on options :by #'cddr
                                                 :append (list k `',v)))))))

(defmacro defcustomfield (name &body fields)
  "Define (or redefine) custom field NAME: a set of fields a model uses as one
field, e.g. (defcustomfield seo (title :text) (image :media)). Each field is
(NAME TYPE . OPTIONS) as in DEFMODEL, but cannot be a :slug or a :custom field,
nor :unique. A model uses it as (meta :custom :custom-field seo), and its value
is an object of these fields."
  `(register-custom-field (make-custom-field ',name ,(field-forms fields))))

(defun webhook (label url &key only)
  "A webhook for DEFWEBHOOKS. It is sent every event (publish, unpublish, delete,
draft) and the payload's \"event\" says which. ONLY narrows it to one model or a
list of them; without it the webhook fires for every model of the space."
  (make-webhook label url :only only))

(defmacro defwebhooks (&rest webhooks)
  "Set the space's webhooks. Each form is evaluated and must produce a
(webhook label url &key only); a webhook fires for every model unless :only
narrows it. Re-evaluating replaces the whole list."
  `(register-webhooks (list ,@webhooks)))

(defmacro defmodel (name (&key kind preview-url public-url label was) &body fields)
  "Define (or redefine) model NAME. KIND is :list or :object and must be given.
Each field is (NAME TYPE . OPTIONS) and is taken literally, e.g.
(tags :reference :model tag :many t).
WAS names the model this one was called before, and :WAS on a field names the
field it was called before; a deploy renames them and moves the stored content
with them. Both are taken literally and are dropped once the deploy has applied
them, so PULL never brings them back.
:HELP on a field is a string the editor shows under the field's name, to say
what it expects, e.g. (cover :media :help \"1200x630\").
:CUSTOM-FIELD names a custom field made with DEFCUSTOMFIELD, for a :custom
field, e.g. (meta :custom :custom-field seo).
PREVIEW-URL and PUBLIC-URL are evaluated; they are URL templates for the admin UI,
starting with http:// or https://, where {CONTENT_ID} and {DRAFT_KEY} are
substituted, e.g.
\"https://example.com/blog/{CONTENT_ID}?draft-key={DRAFT_KEY}\".
LABEL names the :text or :slug field whose value the admin UI shows for a
content -- in lists, reference pickers and the history. Without one a content
is shown by its id."
  (unless (member kind '(:list :object))
    (error "defmodel ~(~a~): :kind must be given as :list or :object, got ~s" name kind))
  `(register-model
    (make-model ',name ,kind
                ,(field-forms fields)
                :preview-url ,preview-url
                :public-url ,public-url
                :label ',label
                :was ',was)))

(defun current-schema ()
  "Return the validated schema built from all definitions so far."
  (check-schema (make-schema :webhooks *webhooks*
                             :custom-fields (mapcar #'cdr *custom-fields*)
                             :models (mapcar #'cdr *models*))))
