(defpackage #:koya-server/usecases/spaces
  (:use #:cl)
  (:import-from #:koya-core/schema #:slug-name-p)
  (:import-from #:koya-server/domain/errors #:fail #:conflict #:invalid-input #:not-found)
  (:import-from #:koya-server/domain/key #:new-webhook-secret)
  (:import-from #:koya-server/usecases/ports/spaces
                #:insert-space #:delete-space #:find-space #:list-spaces)
  (:import-from #:koya-server/usecases/media #:remove-space-media)
  (:export #:create-space
           #:remove-space
           #:find-space
           #:resolve-space
           #:list-spaces))
(in-package #:koya-server/usecases/spaces)

(defun create-space (name)
  (let ((name (string-downcase (string-trim " " name))))
    (unless (slug-name-p name)
      (fail 'invalid-input (format nil "Space name ~s must be lowercase letters, digits and hyphens" name)))
    (when (find-space name)
      (fail 'conflict (format nil "Space ~a already exists" name)))
    (insert-space name (new-webhook-secret))))

(defun remove-space (name)
  (delete-space name)
  (remove-space-media name))

(defun resolve-space (space-name)
  (or (find-space space-name)
      (fail 'not-found (format nil "Space ~a does not exist" space-name))))
