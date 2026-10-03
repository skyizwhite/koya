(defpackage #:koya-server/domain/deploy
  (:use #:cl)
  (:export #:deploy #:make-deploy
           #:deploy-id #:deploy-space #:deploy-changes #:deploy-change-count
           #:deploy-destructive #:deploy-by #:deploy-created-at
           #:change #:make-change
           #:change-op #:change-destructive #:change-description
           #:changes-by-served-model))
(in-package #:koya-server/domain/deploy)

(defstruct deploy
  id space changes change-count destructive by created-at)

(defstruct change
  op destructive description)

(defparameter +ops-that-change-what-is-served+
  '(:rename-model :remove-model :rename-field :remove-field :change-field-type :change-kind))

(defun changes-by-served-model (changes)
  (let ((by-model '()))
    (dolist (change changes (nreverse (mapcar (lambda (entry) (cons (car entry) (reverse (cdr entry)))) by-model)))
      (when (member (getf change :op) +ops-that-change-what-is-served+)
        (let ((entry (assoc (getf change :model) by-model :test #'equal)))
          (if entry
              (push change (cdr entry))
              (push (list (getf change :model) change) by-model)))))))
