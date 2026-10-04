(defpackage #:koya-sdk/config
  (:use #:cl)
  (:import-from #:koya-core/schema
                #:make-field
                #:make-model
                #:make-webhook
                #:make-schema
                #:check-schema
                #:model-name
                #:model-was)
  (:export #:defwebhooks
           #:defmodel
           #:webhook
           #:current-schema
           #:clear-schema
           #:find-model))
(in-package #:koya-sdk/config)

(defvar *webhooks* '())

(defvar *models* '())

(defun clear-schema ()
  "Forget every model and webhook defined so far."
  (setf *webhooks* '()
        *models* '()))

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
                (list ,@(loop :for (fname ftype . options) :in fields
                              :collect `(make-field ',fname ,ftype
                                                    ,@(loop :for (k v) :on options :by #'cddr
                                                            :append (list k `',v)))))
                :preview-url ,preview-url
                :public-url ,public-url
                :label ',label
                :was ',was)))

(defun current-schema ()
  "Return the validated schema built from all definitions so far."
  (check-schema (make-schema :webhooks *webhooks* :models (mapcar #'cdr *models*))))
