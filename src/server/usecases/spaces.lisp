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

;;; A space is made and taken away in the admin UI, never by a deploy: it owns
;;; the contents, media, keys and webhook secret, so its life is longer than any
;;; one schema.

(defun create-space (name)
  "Make a space. NAME is its id: it is in every URL and in the delivery API, so it
never changes. Returns the name; signals INVALID-INPUT for a bad one and CONFLICT
for a taken one."
  (let ((name (string-downcase (string-trim " " name))))
    (unless (slug-name-p name)
      (fail 'invalid-input (format nil "Space name ~s must be lowercase letters, digits and hyphens" name)))
    (when (find-space name)
      (fail 'conflict (format nil "Space ~a already exists" name)))
    (insert-space name (new-webhook-secret))))

(defun remove-space (name)
  ;; the rows go first: the cascade takes the media rows with the space, and
  ;; only then is there nothing left pointing at the files
  (delete-space name)
  (remove-space-media name))

(defun resolve-space (space-name)
  "SPACE-NAME, or signal NOT-FOUND."
  (or (find-space space-name)
      (fail 'not-found (format nil "Space ~a does not exist" space-name))))
