(defpackage #:koya/config
  (:use #:cl)
  (:import-from #:koya/core/schema
                #:make-field
                #:make-model
                #:make-webhook
                #:make-schema
                #:check-schema
                #:model-name)
  (:export #:defwebhooks
           #:defmodel
           #:webhook
           #:current-schema
           #:clear-schema
           #:find-model))
(in-package #:koya/config)

;;; The configuration DSL used by projects that depend on koya. A project defines
;;; one space's models; the space itself is made in the admin UI and named by
;;; KOYA:*SPACE*, so no definition here repeats it. Definitions are collected into
;;; an in-memory registry; CURRENT-SCHEMA turns it into a validated schema that
;;; DEPLOY sends to the server.
;;;
;;;   (defwebhooks
;;;     (webhook "revalidate" "https://example.com/api/revalidate")
;;;     (webhook "preview-build" "https://preview.example/hook" :only 'blog))
;;;
;;;   (defmodel blog (:kind :list)
;;;     (title        :text :required t)
;;;     (content      :richtext)
;;;     (published-at :datetime))
;;;
;;; Re-evaluating a form replaces the previous definition of the same name,
;;; so definitions can be edited live from the REPL.

(defvar *webhooks* '()
  "Webhooks every model of the space fires.")

(defvar *models* '()
  "Ordered alist of model-name -> model, in definition order.")

(defun clear-schema ()
  (setf *webhooks* '()
        *models* '()))

(defun model-key (name) (string-downcase (string name)))

(defun find-model (name)
  (cdr (assoc (model-key name) *models* :test #'string=)))

(defun register-webhooks (webhooks)
  ;; checked here, not at deploy time, so a malformed hook is signalled where it
  ;; was typed; the schema built for the check is thrown away
  (make-schema :webhooks webhooks)
  (setf *webhooks* webhooks))

(defun register-model (model)
  (let* ((key (model-name model))
         (entry (assoc key *models* :test #'string=)))
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

(defmacro defmodel (name (&key kind preview-url public-url) &body fields)
  "Define (or redefine) model NAME. KIND is :list or :object and must be given.
Each field is (NAME TYPE . OPTIONS) and is taken literally, e.g.
(tags :reference :model tag :many t).
PREVIEW-URL and PUBLIC-URL are evaluated; they are URL templates for the admin UI
where {CONTENT_ID} and {DRAFT_KEY} are substituted, e.g.
\"https://example.com/blog/{CONTENT_ID}?draft-key={DRAFT_KEY}\"."
  (unless (member kind '(:list :object))
    (error "defmodel ~(~a~): :kind must be given as :list or :object, got ~s" name kind))
  `(register-model
    (make-model ',name ,kind
                (list ,@(loop :for (fname ftype . options) :in fields
                              :collect `(make-field ',fname ,ftype
                                                    ,@(loop :for (k v) :on options :by #'cddr
                                                            :append (list k `',v)))))
                :preview-url ,preview-url
                :public-url ,public-url)))

(defun current-schema ()
  "Return the validated schema built from all definitions so far."
  (check-schema (make-schema :webhooks *webhooks* :models (mapcar #'cdr *models*))))
