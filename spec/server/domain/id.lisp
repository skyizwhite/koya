(defpackage #:koya-spec/server/domain/id
  (:use #:cl #:rove)
  (:import-from #:koya-server/domain/id #:new-id)
  (:import-from #:cl-ppcre #:scan)
  (:export #:with-drawn-ids))
(in-package #:koya-spec/server/domain/id)

(defun with-drawn-ids (ids thunk)
  (let ((original (fdefinition 'new-id)))
    (unwind-protect
         (progn (setf (fdefinition 'new-id) (lambda () (or (pop ids) (error "No drawn id is left"))))
                (funcall thunk))
      (setf (fdefinition 'new-id) original))))

(deftest an-id-koya-makes-is-twelve-letters-and-digits
  (let ((ids (loop :repeat 100 :collect (new-id))))
    (ok (every (lambda (id) (scan "^[0-9a-z]{12}\\z" id)) ids) "lowercase letters and digits, twelve of them")
    (ok (= (length (remove-duplicates ids :test #'string=)) 100) "drawn at random")))
