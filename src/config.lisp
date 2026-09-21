(defpackage #:koya/config
  (:use #:cl)
  (:import-from #:koya/core/schema
                #:schema-error
                #:make-field
                #:make-model
                #:make-webhook
                #:make-space
                #:make-schema
                #:check-schema
                #:space-name
                #:space-webhooks
                #:space-models
                #:model-name)
  (:export #:defspace
           #:defmodel
           #:webhook
           #:current-schema
           #:clear-schema
           #:find-space
           #:find-model))
(in-package #:koya/config)

;;; The configuration DSL used by projects that depend on koya. Definitions are
;;; collected into an in-memory registry; CURRENT-SCHEMA turns it into a
;;; validated schema that DEPLOY sends to the server.
;;;
;;;   (defspace website :webhooks (list (webhook "revalidate" "https://example.com/api/revalidate"
;;;                                   :events '(:publish :unpublish :delete))))
;;;
;;;   (defmodel (website blog) (:kind :list)
;;;     (title        :text :required t)
;;;     (content      :richtext)
;;;     (published-at :datetime))
;;;
;;; Re-evaluating a form replaces the previous definition of the same name,
;;; so definitions can be edited live from the REPL.

(defvar *spaces* '()
  "Ordered alist of space-name -> space-def, in definition order.")

(defun clear-schema ()
  (setf *spaces* '()))

(defun space-key (name) (string-downcase (string name)))

(defun find-space (name)
  (cdr (assoc (space-key name) *spaces* :test #'string=)))

(defun find-model (space model)
  (let ((space (find-space space)))
    (and space (find (space-key model) (space-models space) :key #'model-name :test #'string=))))

(defun register-space (name &key webhooks)
  (let* ((key (space-key name))
         (existing (find-space key))
         (space (make-space key :webhooks webhooks :models (and existing (space-models existing)))))
    (if existing
        (setf (cdr (assoc key *spaces* :test #'string=)) space)
        (setf *spaces* (append *spaces* (list (cons key space)))))
    space))

(defun register-model (space-name model)
  (let* ((key (space-key space-name))
         (space (or (find-space key)
                    (error "defmodel: space ~s is not defined. Use defspace first." key)))
         (models (space-models space))
         (position (position (model-name model) models :key #'model-name :test #'string=))
         (new-models (if position
                         (append (subseq models 0 position) (list model) (subseq models (1+ position)))
                         (append models (list model)))))
    (setf (cdr (assoc key *spaces* :test #'string=))
          (make-space key :webhooks (space-webhooks space) :models new-models))
    model))

(defun webhook (label url &key (events nil events-p))
  "A webhook for :webhooks of defspace or defmodel. EVENTS must be given: a non-empty
list from (:publish :unpublish :delete :draft) saying when it fires."
  (unless events-p
    (error 'schema-error :message (format nil "webhook ~s: :events must be given, e.g. :events '(:publish :unpublish :delete)" label)))
  (make-webhook label url :events events))

(defmacro defspace (name &key webhooks)
  "Define (or redefine) a space. WEBHOOKS is evaluated: a list of (webhook ...) that
every model of the space fires."
  `(register-space ',name :webhooks ,webhooks))

(defmacro defmodel ((space name) (&key kind preview-url public-url webhooks) &body fields)
  "Define (or redefine) model NAME in SPACE. KIND is :list or :object and must be
given. Each field is (NAME TYPE . OPTIONS) and is taken literally, e.g.
(tags :reference :model tag :many t).
PREVIEW-URL and PUBLIC-URL are evaluated; they are URL templates for the admin UI
where {CONTENT_ID} and {DRAFT_KEY} are substituted, e.g.
\"https://example.com/blog/{CONTENT_ID}?draft-key={DRAFT_KEY}\"."
  (unless (member kind '(:list :object))
    (error "defmodel (~(~a ~a~)): :kind must be given as :list or :object, got ~s" space name kind))
  `(register-model ',space
                   (make-model ',name ,kind
                               (list ,@(loop :for (fname ftype . options) :in fields
                                             :collect `(make-field ',fname ,ftype
                                                                   ,@(loop :for (k v) :on options :by #'cddr
                                                                           :append (list k `',v)))))
                               :preview-url ,preview-url
                               :public-url ,public-url
                               :webhooks ,webhooks)))

(defun current-schema ()
  "Return the validated schema built from all definitions so far."
  (check-schema (make-schema (mapcar #'cdr *spaces*))))
