(defpackage #:koya-spec/server/domain/content
  (:use #:cl #:rove)
  (:import-from #:koya-server/domain/content
                #:next-status #:check-transition #:make-content #:+statuses+ #:+operations+)
  (:import-from #:koya-server/domain/errors #:conflict #:koya-error-code))
(in-package #:koya-spec/server/domain/content)

(defun content-in (status)
  (make-content :id "c"
                :published (and (member status '("published" "published+draft") :test #'string=) :data)
                :draft (and (member status '("draft" "published+draft") :test #'string=) :data)))

(defun refusal (status op)
  (handler-case (progn (check-transition (content-in status) op) nil)
    (conflict (e) (koya-error-code e))))

(deftest every-operation-in-every-status-is-decided
  (dolist (status +statuses+)
    (dolist (op +operations+)
      (multiple-value-bind (next allowed) (next-status status op)
        (declare (ignore next))
        (ok (if allowed (null (refusal status op)) (stringp (refusal status op)))
            (format nil "~a on ~a is either a transition or a refusal with a code" op status))))))

(deftest the-transitions
  (flet ((to (status op) (multiple-value-list (next-status status op))))
    (testing "a draft is saved, published or deleted"
      (ok (equal (to "draft" :save) '("draft" t)))
      (ok (equal (to "draft" :publish) '("published" t)))
      (ok (equal (to "draft" :delete) '(nil t)) "a delete leaves no content"))
    (testing "a published content is saved to a draft, published again, unpublished or deleted"
      (ok (equal (to "published" :save) '("published+draft" t)))
      (ok (equal (to "published" :publish) '("published" t)) "publishing again stays published")
      (ok (equal (to "published" :unpublish) '("draft" t)))
      (ok (equal (to "published" :delete) '(nil t))))
    (testing "a published content with a draft can do everything"
      (ok (equal (to "published+draft" :save) '("published+draft" t)))
      (ok (equal (to "published+draft" :publish) '("published" t)))
      (ok (equal (to "published+draft" :unpublish) '("draft" t)))
      (ok (equal (to "published+draft" :discard) '("published" t)))
      (ok (equal (to "published+draft" :delete) '(nil t))))
    (testing "what a status cannot do is refused, with why"
      (ok (equal (refusal "draft" :unpublish) "not_published"))
      (ok (equal (refusal "draft" :discard) "not_published"))
      (ok (equal (refusal "published" :discard) "no_draft")))))
