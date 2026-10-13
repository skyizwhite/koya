(defpackage #:koya-spec/server/domain/content
  (:use #:cl #:rove)
  (:import-from #:koya-server/domain/content
                #:next-status #:check-transition #:make-content #:+statuses+ #:+operations+ #:held-ids
                #:new-content #:drafted #:published #:unpublished #:discarded #:content-status
                #:content-published-p #:content-draft-p #:content-data
                #:merge-data #:comparable-data #:initial-data #:to-the-minute #:content-labels)
  (:import-from #:koya-core/data #:data-equal)
  (:import-from #:koya-core/schema #:make-model #:make-field)
  (:import-from #:koya-server/domain/errors #:conflict #:koya-error-code))
(in-package #:koya-spec/server/domain/content)

(defun content-in (status)
  (make-content :id "c" :status status))

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

(deftest the-ids-a-reference-or-media-holds
  (testing "one that holds many"
    (ok (equal (held-ids (vector "b" "a" "b") t) '("b" "a" "b")) "holds what its list names, in order, as often as named")
    (ok (equal (held-ids (vector "a" "" 5) t) '("a")) "but not a blank or what is not an id")
    (ok (null (held-ids "a" t)) "and nothing when it has no list"))
  (testing "one that holds one"
    (ok (equal (held-ids "a" nil) '("a")))
    (ok (null (held-ids "" nil)) "holds nothing when it is blank")
    (ok (null (held-ids (vector "a") nil)) "or has a list")))

(deftest contents-are-named-by-their-label
  (let ((contents (make-hash-table :test 'equal))
        (model (make-model "tag" :list (list (make-field :name :text)) :label "name")))
    (setf (gethash "a" contents) (make-content :id "a" :status "draft" :draft (list :name "Lisp"))
          (gethash "b" contents) (make-content :id "b" :status "draft" :draft (list :name "")))
    (let ((labels (content-labels contents model)))
      (ok (string= (gethash "a" labels) "Lisp") "each id is named by its content's label")
      (ok (string= (gethash "b" labels) "b") "or by itself when the label is blank")
      (ok (= (hash-table-count labels) 2)))))

(deftest a-content-s-status-says-which-versions-it-has
  (let ((live (new-content "c" "s" "m" nil :publish t)))
    (ok (string= (content-status live) "published") "data with no values is a version still")
    (ok (content-published-p live))
    (ng (content-draft-p live))
    (let ((both (drafted live nil)))
      (ok (string= (content-status both) "published+draft") "and so is an empty draft")
      (ok (content-draft-p both))
      (ok (string= (content-status (discarded both)) "published"))
      (ok (string= (content-status (unpublished both)) "draft"))
      (ok (string= (content-status (published both nil)) "published")))
    (ok (string= (content-status (drafted (new-content "c" "s" "m" (list :a 1)) nil)) "draft")
        "a draft saved again is a draft"))
  (testing "the data of a version it has"
    (let ((both (make-content :status "published+draft" :published (list :a 1) :draft nil)))
      (ok (null (content-data both :draft t)) "an empty draft is the draft")
      (ok (equal (content-data both) '(:a 1))))
    (ok (equal (content-data (make-content :status "published" :published (list :a 1) :draft (list :a 2)) :draft t)
               '(:a 1))
        "and not one it has not")))

(deftest a-patch-is-merged-key-by-key
  (ok (equal (merge-data (list :a 1 :b 2) (list :b :null :c 3)) '(:c 3 :a 1)) "null clears, a value sets")
  (ok (equal (merge-data (list :a 1) (list :a 2)) '(:a 2)))
  (ok (equal (merge-data (list :blog-post "a") (list "blog-post" "b")) '("blog-post" "b" :blog-post "a"))
      "a string key does not take the place of a keyword spelled the same")
  (let ((base (list :a 1)))
    (merge-data base (list :a 2))
    (ok (equal base '(:a 1)) "and the data merged into is left as it was")))

(deftest data-taken-in
  (let ((model (make-model "m" :list (list (make-field :at :datetime)
                                           (make-field :on :boolean :default t)
                                           (make-field :off :boolean)
                                           (make-field :title :text)))))
    (ok (equal (initial-data model (list :at "2026-10-12T10:20:30Z" :title :null))
               '(:on t :at "2026-10-12T10:20:00.000Z"))
        "a new content keeps no null, has its defaults and its times to the minute")
    (ok (null (initial-data model (list :on :null)))
        "and a boolean given null is given, so no default is filled in for it")
    (ok (equal (to-the-minute model (list :at "2026-10-12T10:20:30Z" :title :null :on nil))
               '(:at "2026-10-12T10:20:00.000Z" :on nil))
        "saved data keeps no null either, and no default is filled in")
    (ok (data-equal (comparable-data model (list :title "a" :on :null)) (list :title "a" :on nil :off nil))
        "data is compared with every boolean there, one not given or null as false")))
