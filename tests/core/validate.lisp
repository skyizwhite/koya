(defpackage #:koya-tests/core/validate
  (:use #:cl #:rove)
  (:import-from #:koya/core/schema
                #:make-field #:make-model)
  (:import-from #:koya/core/validate
                #:validate-content)
  (:import-from #:koya/core/json
                #:parse-json))
(in-package #:koya-tests/core/validate)

(defparameter *model*
  (make-model "blog" :list
              (list (make-field :title :text :required t :max-length 10 :pattern "^[A-Z]")
                    (make-field :slug :slug :from :title)
                    (make-field :body :richtext)
                    (make-field :count :number :integer t :min 0 :max 10)
                    (make-field :featured :boolean)
                    (make-field :day :date)
                    (make-field :event-at :datetime :required t)
                    (make-field :category :select :options (quote ("news" "tech")))
                    (make-field :labels :select :options (quote ("a" "b")) :many t)
                    (make-field :tags :reference :model "tag" :many t)
                    (make-field :cover :media))))

(defun codes (json)
  (mapcar (lambda (e) (cons (getf e :field) (getf e :code)))
          (validate-content *model* (parse-json json))))

(deftest valid-content
  (ok (null (codes "{\"title\": \"Hello\", \"eventAt\": \"2026-09-20T00:00:00Z\", \"slug\": \"hello-world\",
                     \"count\": 3, \"featured\": true, \"day\": \"2026-09-20\", \"category\": \"news\",
                     \"labels\": [\"a\", \"b\"], \"tags\": [\"01ARZ3NDEKTSV4RRFFQ69G5FAV\"],
                     \"cover\": \"01ARZ3NDEKTSV4RRFFQ69G5FAV\", \"body\": \"# hi\"}")))
  (ok (null (codes "{\"title\": \"Hello\", \"eventAt\": \"2026-09-20T00:00:00Z\", \"featured\": false}"))
      "false boolean is fine"))

(deftest required
  (ok (equal (codes "{}") '(("title" . "required") ("eventAt" . "required"))))
  (ok (equal (codes "{\"title\": \"  \", \"eventAt\": null}")
             '(("title" . "required") ("eventAt" . "required")))
      "blank and null count as missing")
  (testing "partial skips missing fields"
    (ok (null (validate-content *model* (parse-json "{}") :partial t)))
    (ok (equal (mapcar (lambda (e) (getf e :code))
                       (validate-content *model* (parse-json "{\"title\": null}") :partial t))
               '("required")))))

(deftest false-and-empty-array-are-values
  (ok (equal (codes "{\"title\": false, \"eventAt\": \"2026-09-20T00:00:00Z\", \"count\": false}")
             '(("title" . "type") ("count" . "type")))
      "false is only a boolean")
  (ok (equal (codes "{\"title\": [], \"eventAt\": \"2026-09-20T00:00:00Z\"}")
             '(("title" . "type")))
      "[] on a single-value field")
  (ok (null (codes "{\"title\": \"Ok\", \"eventAt\": \"2026-09-20T00:00:00Z\", \"labels\": [], \"tags\": []}"))
      "[] on a many field is blank"))

(deftest type-errors
  (ok (equal (codes "{\"title\": 1, \"eventAt\": \"nope\"}")
             '(("title" . "type") ("eventAt" . "type"))))
  (ok (equal (codes "{\"title\": \"Toolongtitle!\", \"eventAt\": \"2026-09-20T00:00:00Z\"}")
             '(("title" . "max_length"))))
  (ok (equal (codes "{\"title\": \"lower\", \"eventAt\": \"2026-09-20T00:00:00Z\"}")
             '(("title" . "pattern"))))
  (ok (equal (codes "{\"title\": \"Ok\", \"eventAt\": \"2026-09-20T00:00:00Z\", \"slug\": \"Not Slug\"}")
             '(("slug" . "slug"))))
  (ok (equal (codes "{\"title\": \"Ok\", \"eventAt\": \"2026-09-20T00:00:00Z\", \"count\": 2.5}")
             '(("count" . "integer"))))
  (ok (equal (codes "{\"title\": \"Ok\", \"eventAt\": \"2026-09-20T00:00:00Z\", \"count\": 11}")
             '(("count" . "max"))))
  (ok (equal (codes "{\"title\": \"Ok\", \"eventAt\": \"2026-09-20T00:00:00Z\", \"featured\": \"yes\"}")
             '(("featured" . "type"))))
  (ok (equal (codes "{\"title\": \"Ok\", \"eventAt\": \"2026-09-20T00:00:00Z\", \"day\": \"2026-9-20\"}")
             '(("day" . "type"))))
  (ok (equal (codes "{\"title\": \"Ok\", \"eventAt\": \"2026-02-30T00:00:00Z\", \"day\": \"2026-02-30\"}")
             '(("day" . "type") ("eventAt" . "type")))
      "calendar-invalid dates are type errors, not crashes")
  (ok (equal (codes "{\"title\": \"Ok\", \"eventAt\": \"2026-09-20\"}")
             '(("eventAt" . "type")))
      "a datetime needs a time and a zone")
  (ok (null (codes "{\"title\": \"Ok\", \"eventAt\": \"2026-09-20T09:00:00+09:00\"}")) "offsets are fine")
  (ok (equal (codes "{\"title\": \"Ok\", \"eventAt\": \"2026-09-20T00:00:00Z\", \"category\": \"sports\"}")
             '(("category" . "option"))))
  (ok (equal (codes "{\"title\": \"Ok\", \"eventAt\": \"2026-09-20T00:00:00Z\", \"labels\": \"a\"}")
             '(("labels" . "type")))
      "many requires an array")
  (ok (equal (codes "{\"title\": \"Ok\", \"eventAt\": \"2026-09-20T00:00:00Z\", \"cover\": \"abc\\n\", \"slug\": \"ok\\n\", \"day\": \"2026-09-20\\n\"}")
             '(("slug" . "slug") ("day" . "type") ("cover" . "type")))
      "a trailing newline is not accepted by anchored patterns")
  (ok (equal (codes "{\"title\": \"Ok\", \"eventAt\": \"2026-09-20T00:00:00Z\", \"tags\": [\"bad id!\"]}")
             '(("tags" . "type"))))
  (ok (equal (codes "{\"title\": \"Ok\", \"eventAt\": \"2026-09-20T00:00:00Z\", \"extra\": 1}")
             '(("extra" . "unknown_field")))))
