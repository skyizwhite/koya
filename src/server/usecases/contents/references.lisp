(defpackage #:koya-server/usecases/contents/references
  (:use #:cl)
  (:import-from #:koya-server/domain/references
                #:reference-fields #:refers-p)
  (:import-from #:koya-server/usecases/ports/spaces
                #:load-schema)
  (:import-from #:koya-server/usecases/ports/contents
                #:contents-mentioning)
  (:export #:content-references))
(in-package #:koya-server/usecases/contents/references)

(defun content-references (space model id)
  "Number of other contents in SPACE whose published or draft data refers to
content ID of MODEL through a :reference field of the current schema."
  (let ((fields (reference-fields (load-schema space) model)))
    (if (zerop (hash-table-count fields))
        0
        (count-if (lambda (content) (refers-p content fields id))
                  (contents-mentioning space id :exclude-id id)))))
