(defpackage #:koya-server/usecases/contents/lookup
  (:use #:cl)
  (:import-from #:koya-server/domain/errors
                #:fail #:not-found)
  (:import-from #:koya-server/usecases/ports/spaces
                #:find-space #:find-model)
  (:import-from #:koya-server/usecases/ports/contents
                #:find-content)
  (:export #:resolve-model
           #:resolve-content
           #:find-content))
(in-package #:koya-server/usecases/contents/lookup)

;;; Finding what a request names, or saying it is not there.

(defun resolve-model (space-name model-name)
  "Return (values space-name model), or signal NOT-FOUND."
  (let* ((space (or (find-space space-name)
                    (fail 'not-found (format nil "Space ~a does not exist" space-name))))
         (model (or (find-model space model-name)
                    (fail 'not-found (format nil "Model ~a does not exist" model-name)))))
    (values space model)))

(defun resolve-content (space-name model-name id)
  (or (find-content space-name model-name id)
      (fail 'not-found (format nil "Content ~a does not exist" id))))
