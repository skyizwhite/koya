(defpackage #:koya-spec/server/usecases/contents
  (:use #:cl #:rove)
  (:import-from #:koya-server/domain/errors #:conflict #:invalid-input)
  (:import-from #:koya-server/domain/key #:key-id #:key-label)
  (:import-from #:koya-server/usecases/schema #:replace-schema)
  (:import-from #:koya-server/infra/db/connection
                #:connect-db #:disconnect-db #:fetch-one #:col #:exec)
  (:import-from #:koya-server/infra/db/migrations #:migrate)
  (:import-from #:koya-server/usecases/ports/spaces #:find-model)
  (:import-from #:koya-server/usecases/spaces #:create-space)
  (:import-from #:koya-server/usecases/ports/contents
                #:get-content #:find-content #:list-contents
                #:find-object-content #:unique-value-taken-p #:list-revisions
                #:count-revisions #:find-revision)
  (:import-from #:koya-server/usecases/contents
                #:create #:update-draft #:publish #:unpublish #:discard #:destroy #:draft-key)
  (:import-from #:koya-server/usecases/actor #:*actor*)
  (:import-from #:koya-server/domain/content
                #:content-id #:content-status #:content-published #:content-draft
                #:content-published-at #:content-revised-at #:content-draft-key
                #:content-created-at #:content-updated-at)
  (:import-from #:koya-server/domain/revision
                #:revision-id #:revision-event #:revision-data #:revision-by)
  (:import-from #:koya-server/usecases/keys
                #:create-delivery-key #:list-delivery-keys #:delete-delivery-key
                #:space-for-delivery-key)
  (:import-from #:koya-server/domain/query
                #:parse-query #:make-query #:query-limit #:query-offset #:query-orders
                #:query-filters #:query-fields #:query-include #:query-error)
  (:import-from #:koya-core/validate #:validation-error)
  (:import-from #:koya-core/schema #:make-field #:make-model #:make-schema)
  (:import-from #:koya-core/json #:parse-json #:jget))
(in-package #:koya-spec/server/usecases/contents)

(defun blog-model ()
  (make-model "blog" :list (list (make-field :title :text :required t :unique t)
                                 (make-field :body :richtext)
                                 (make-field :count :number)
                                 (make-field :featured :boolean)
                                 (make-field :tags :reference :model "tag" :many t)
                                 (make-field :day :date))))

(setup
  (connect-db ":memory:")
  (migrate)
  (create-space "website")
  (replace-schema "website"
               (make-schema :models (list (blog-model)
                                          (make-model "tag" :list (list (make-field :name :text)))
                                          (make-model "event" :list (list (make-field :at :datetime)))
                                          (make-model "page" :list (list (make-field :title :text)
                                                                         (make-field :slug :slug :from :title)))
                                          (make-model "about" :object (list (make-field :body :richtext)))))))

(teardown (disconnect-db))

(defhook :before (exec "DELETE FROM contents"))

(defvar *read-eval-probe* nil)

(defun data (json) (parse-json json))
(defun blog () (find-model "website" "blog"))
(defun make (json &rest args)
  (apply #'create "website" (blog) (data json) args))
(defun q (&rest kv) (parse-query (loop :for (k v) :on kv :by #'cddr :collect (cons k v))))
(defun titles (contents) (mapcar (lambda (c) (jget (content-published c) "title")) contents))

(deftest lifecycle
  (let ((c (make "{\"title\": \"Draft one\"}")))
    (ok (string= (content-status c) "draft"))
    (ok (null (content-published c)))
    (ok (string= (jget (content-draft c) "title") "Draft one"))
    (ok (null (content-published-at c)))
    (let ((p (publish "website" (blog) (content-id c))))
      (ok (string= (content-status p) "published"))
      (ok (string= (jget (content-published p) "title") "Draft one"))
      (ok (null (content-draft p)))
      (ok (content-published-at p))
      (let ((d (update-draft "website" (blog) (content-id c) (data "{\"title\": \"Edited\"}"))))
        (ok (string= (content-status d) "published+draft"))
        (ok (string= (jget (content-published d) "title") "Draft one") "published untouched by a draft save")
        (ok (string= (jget (content-draft d) "title") "Edited"))
        (let ((p2 (publish "website" (blog) (content-id c))))
          (ok (string= (jget (content-published p2) "title") "Edited") "publish promotes the draft")
          (ok (string= (content-published-at p2) (content-published-at p)) "first publish date is kept")
          (ok (string>= (content-revised-at p2) (content-revised-at p)))
          (let ((u (unpublish "website" (blog) (content-id c))))
            (ok (string= (content-status u) "draft"))
            (ok (null (content-published u)))
            (ok (null (content-published-at u)) "an unpublished content has no publish date")
            (ok (null (content-revised-at u)) "nor a revision date")
            (ok (string= (jget (content-draft u) "title") "Edited") "unpublish keeps the data as draft")
            (ok (string= (content-status (get-content "website" (content-id c))) "draft") "and that is what is stored"))))
      (destroy "website" (blog) (content-id c))
      (ng (get-content "website" (content-id c))))))

(deftest every-write-leaves-a-revision
  (let* ((c (let ((*actor* "owner")) (make "{\"title\": \"One\"}")))
         (id (content-id c)))
    (let ((*actor* "key:ci")) (update-draft "website" (blog) id (data "{\"title\": \"Two\"}")))
    (update-draft "website" (blog) id (data "{\"title\": \"Two\"}"))
    (publish "website" (blog) id)
    (update-draft "website" (blog) id (data "{\"title\": \"Three\"}"))
    (discard "website" (blog) id)
    (unpublish "website" (blog) id)
    (let ((revisions (list-revisions "website" id)))
      (ok (equal (mapcar #'revision-event revisions) '("unpublish" "discard" "draft" "publish" "draft" "draft"))
          "newest first; the second save of the same data is not an event")
      (ok (equal (mapcar (lambda (r) (jget (revision-data r) "title")) revisions)
                 '("Two" "Two" "Three" "Two" "Two" "One"))
          "each holds what the write left the content with")
      (ok (equal (mapcar #'revision-by (last revisions 2)) '("key:ci" "owner")))
      (ok (string= (revision-by (first revisions)) "") "a write that names nobody stores nobody"))
    (testing "the published ones are the versions that were live"
      (ok (= (count-revisions "website" id :published-only t) 1))
      (ok (equal (mapcar #'revision-event (list-revisions "website" id :published-only t)) '("publish"))))
    (testing "what changes nothing that was live is not an event"
      (let* ((draft (make "{\"title\": \"Never live\"}"))
             (live (make "{\"title\": \"Live\"}" :publish t)))
        (ok (signals (unpublish "website" (blog) (content-id draft)) 'conflict)
            "a content that was never published cannot be unpublished")
        (ok (equal (mapcar #'revision-event (list-revisions "website" (content-id draft))) '("draft")) "and nothing is kept")
        (ok (signals (discard "website" (blog) (content-id draft)) 'conflict)
            "a content that was never published has no draft to discard, only itself")
        (ok (signals (discard "website" (blog) (content-id live)) 'conflict)
            "a published content with no draft has none to discard")
        (ok (equal (mapcar #'revision-event (list-revisions "website" (content-id live))) '("publish")) "and nothing is kept")))
    (testing "a revision belongs to its content"
      (let ((other (make "{\"title\": \"Other\"}")))
        (ng (find-revision "website" (content-id other) (revision-id (first (list-revisions "website" id)))))))
    (testing "deleting the content deletes its history"
      (destroy "website" (blog) id)
      (ok (zerop (col (fetch-one "SELECT COUNT(*) AS n FROM content_revisions WHERE content_id = ?" id) "n"))))))

(deftest draft-keys
  (let* ((c (make "{\"title\": \"x\"}"))
         (key (content-draft-key c)))
    (ok (= (length key) 32) "a draft gets a key on creation")
    (ok (string= key (draft-key "website" "blog" (content-id c))) "asking for it returns the current key")
    (let ((saved (update-draft "website" (blog) (content-id c) (data "{\"title\": \"y\"}"))))
      (ok (string/= (content-draft-key saved) key) "every draft save rotates the key")
      (ok (null (content-draft-key (publish "website" (blog) (content-id c)))) "publishing clears it")
      (ok (content-draft-key (unpublish "website" (blog) (content-id c))) "unpublishing issues a new one"))
    (let ((p (make "{\"title\": \"pub\"}" :publish t)))
      (ok (null (content-draft-key p)) "published content has no key")
      (let ((made (draft-key "website" "blog" (content-id p))))
        (ok (= (length made) 32) "but one can be made on demand")
        (ok (string= made (content-draft-key (get-content "website" (content-id p)))) "and is kept")))))

(deftest object-content
  (ng (find-object-content "website" "about"))
  (create "website" (find-model "website" "about") (data "{\"body\": \"hi\"}") :publish t)
  (ok (string= (jget (content-published (find-object-content "website" "about")) "body") "hi")))

(deftest uniqueness
  (let ((c (make "{\"title\": \"Taken\"}" :publish t)))
    (ok (unique-value-taken-p "website" "blog" "title" "Taken"))
    (ng (unique-value-taken-p "website" "blog" "title" "Taken" :exclude-id (content-id c)) "the content itself does not count")
    (ng (unique-value-taken-p "website" "blog" "title" "Free"))
    (update-draft "website" (blog) (content-id (make "{\"title\": \"z\"}")) (data "{\"title\": \"In draft\"}"))
    (ok (unique-value-taken-p "website" "blog" "title" "In draft") "drafts count too")))

(deftest listing
  (make "{\"title\": \"Alpha\", \"count\": 1, \"featured\": true, \"tags\": [\"01ARZ3NDEKTSV4RRFFQ69G5FAV\"], \"day\": \"2026-01-01\"}" :publish t)
  (make "{\"title\": \"Beta\", \"count\": 5, \"featured\": false, \"tags\": [], \"day\": \"2026-02-01\"}" :publish t)
  (make "{\"title\": \"Gamma\", \"count\": 10, \"day\": \"2026-03-01\"}" :publish t)
  (make "{\"title\": \"Hidden draft\"}")
  (let ((model (find-model "website" "blog")))
    (testing "published only, newest first, total count"
      (multiple-value-bind (contents total) (list-contents "website" "blog" model (q))
        (ok (= total 3))
        (ok (equal (titles contents) '("Gamma" "Beta" "Alpha")))))
    (testing "admin listing includes drafts"
      (multiple-value-bind (contents total) (list-contents "website" "blog" model (q) :status :all)
        (ok (= total 4))
        (ok (= (length contents) 4))))
    (testing "limit/offset"
      (multiple-value-bind (contents total) (list-contents "website" "blog" model (q "limit" "1" "offset" "1"))
        (ok (= total 3))
        (ok (equal (titles contents) '("Beta"))))
      (ok (null (list-contents "website" "blog" model (q "offset" "9223372036854775807")))
          "the largest offset SQLite can hold reads past the end")
      (ok (signals (q "offset" "9223372036854775808") 'query-error) "and one past it is refused")
      (ok (= (query-limit (q "limit" "99999999999999999999")) 100) "a limit past the most is the most"))
    (testing "orders"
      (ok (equal (titles (list-contents "website" "blog" model (q "orders" "day"))) '("Alpha" "Beta" "Gamma")))
      (ok (equal (titles (list-contents "website" "blog" model (q "orders" "-count"))) '("Gamma" "Beta" "Alpha")))
      (ok (equal (titles (list-contents "website" "blog" model (q "orders" "title"))) '("Alpha" "Beta" "Gamma"))))
    (testing "filters"
      (ok (equal (titles (list-contents "website" "blog" model (q "filters" "title[equals]Beta"))) '("Beta")))
      (ok (equal (titles (list-contents "website" "blog" model (q "filters" "count[greater_than]4"))) '("Gamma" "Beta")))
      (ok (equal (titles (list-contents "website" "blog" model (q "filters" "count[less_than]5[or]count[greater_than]9"))) '("Gamma" "Alpha")))
      (ok (equal (titles (list-contents "website" "blog" model (q "filters" "featured[equals]true"))) '("Alpha")))
      (ok (equal (titles (list-contents "website" "blog" model (q "filters" "title[contains]et"))) '("Beta")))
      (ok (equal (titles (list-contents "website" "blog" model (q "filters" "title[begins_with]G"))) '("Gamma")))
      (ok (equal (titles (list-contents "website" "blog" model (q "filters" "count[exists]"))) '("Gamma" "Beta" "Alpha")))
      (ok (null (list-contents "website" "blog" model (q "filters" "count[not_exists]"))))
      (ok (equal (titles (list-contents "website" "blog" model (q "filters" "tags[contains]01ARZ3NDEKTSV4RRFFQ69G5FAV"))) '("Alpha")))
      (ok (equal (titles (list-contents "website" "blog" model (q "filters" "day[greater_than]2026-01-15[and]count[less_than]10"))) '("Beta")))
      (ok (equal (titles (list-contents "website" "blog" model (q "filters" "title[not_equals]Beta"))) '("Gamma" "Alpha"))))
    (testing "bad queries are rejected"
      (ok (signals (list-contents "website" "blog" model (q "filters" "nope[equals]1")) 'query-error))
      (ok (signals (list-contents "website" "blog" model (q "filters" "count[equals]abc")) 'query-error))
      (ok (signals (list-contents "website" "blog" model (q "filters" "count[equals]1 2")) 'query-error) "trailing garbage")
      (ok (signals (list-contents "website" "blog" model (q "filters" "count[equals]1/3")) 'query-error) "a ratio")
      (ok (signals (list-contents "website" "blog" model (q "filters" "count[equals]#x1f")) 'query-error) "a radix number")
      (ok (signals (list-contents "website" "blog" model
                                  (q "filters" (format nil "count[equals]~a" (make-string 100000 :initial-element #\())))
                   'query-error)
          "deep nesting is rejected, not read")
      (ok (signals (list-contents "website" "blog" model (q "filters" "count[equals]123456789012345678901234567890")) 'query-error)
          "an integer too large to bind")
      (ok (equal (titles (list-contents "website" "blog" model (q "filters" "count[greater_than]4.5e0"))) '("Gamma" "Beta"))
          "a decimal with an exponent")
      (let ((*read-eval-probe* nil))
        (ok (signals (list-contents "website" "blog" model
                                    (q "filters" "count[equals]#.(setf koya-spec/server/usecases/contents::*read-eval-probe* t)"))
                     'query-error)
            "reader macros in a number filter are rejected")
        (ok (null *read-eval-probe*) "and never evaluated"))
      (ok (signals (list-contents "website" "blog" model (q "filters" "title[weird]1")) 'query-error))
      (ok (signals (list-contents "website" "blog" model (q "orders" "nope")) 'query-error))
      (ok (signals (q "limit" "abc") 'query-error)))))

(deftest listing-without-a-limit
  (dotimes (i 12)
    (make (format nil "{\"title\": \"Post ~a\"}" i)))
  (let ((model (find-model "website" "blog")))
    (multiple-value-bind (contents total) (list-contents "website" "blog" model (make-query :limit nil) :status :all)
      (ok (= total 12))
      (ok (= (length contents) 12) "a query whose limit is NIL lists every row"))
    (ok (= (length (list-contents "website" "blog" model (make-query) :status :all)) 10)
        "one made without a limit keeps the default")))

(deftest listing-by-status
  (make "{\"title\": \"Live\"}" :publish t)
  (let ((both (make "{\"title\": \"Live with a draft\"}" :publish t)))
    (update-draft "website" (blog) (content-id both) (data "{\"title\": \"Live with a draft\", \"count\": 1}")))
  (make "{\"title\": \"Only a draft\"}")
  (let ((model (find-model "website" "blog")))
    (flet ((titles-with (status)
             (sort (mapcar (lambda (c) (jget (or (content-draft c) (content-published c)) "title"))
                           (list-contents "website" "blog" model (q "limit" "50")
                                          :status :all :only-status status))
                   #'string<)))
      (ok (equal (titles-with nil) '("Live" "Live with a draft" "Only a draft"))
          "no status is every status")
      (ok (equal (titles-with "draft") '("Only a draft")))
      (ok (equal (titles-with "published") '("Live"))
          "published means published and nothing else pending, which is what the badge says")
      (ok (equal (titles-with "published+draft") '("Live with a draft")))
      (ok (null (titles-with "nonsense")))))
  (testing "it narrows what the search finds, rather than replacing it"
    (let ((model (find-model "website" "blog")))
      (ok (= (nth-value 1 (list-contents "website" "blog" model (q "filters" "title[contains]Live")
                                         :status :all))
             2))
      (ok (= (nth-value 1 (list-contents "website" "blog" model (q "filters" "title[contains]Live")
                                         :status :all :only-status "published"))
             1)))))

(deftest filters-read-blank-and-false-as-the-schema-does
  (make "{\"title\": \"True\", \"featured\": true, \"body\": \"<p>x</p>\", \"tags\": [\"01ARZ3NDEKTSV4RRFFQ69G5FAV\"], \"count\": 0}" :publish t)
  (make "{\"title\": \"False\", \"featured\": false, \"body\": \" \\t\\n \", \"tags\": []}" :publish t)
  (make "{\"title\": \"Missing\"}" :publish t)
  (make "{\"title\": \"Null\", \"featured\": null, \"body\": null, \"tags\": null, \"count\": null}" :publish t)
  (flet ((found (filters)
           (sort (titles (list-contents "website" "blog" (blog) (q "filters" filters))) #'string<)))
    (testing "a missing or null boolean is false"
      (ok (equal (found "featured[equals]false") '("False" "Missing" "Null")))
      (ok (equal (found "featured[not_equals]true") '("False" "Missing" "Null")) "as not true finds it")
      (ok (equal (found "featured[not_equals]false") '("True")))
      (ok (equal (found "featured[equals]true") '("True"))))
    (testing "exists is a value that is not blank"
      (ok (equal (found "body[exists]") '("True")) "a string of whitespace is blank")
      (ok (equal (found "body[not_exists]") '("False" "Missing" "Null")))
      (ok (equal (found "tags[exists]") '("True")) "and so is [] on a many field")
      (ok (equal (found "tags[not_exists]") '("False" "Missing" "Null")))
      (ok (equal (found "count[exists]") '("True")) "zero is a value"))
    (testing "and a boolean always has one"
      (ok (equal (found "featured[exists]") '("False" "Missing" "Null" "True")))
      (ok (null (found "featured[not_exists]"))))))

(deftest a-datetime-is-kept-to-the-minute-in-utc
  (let ((model (find-model "website" "event")))
    (flet ((at (json) (jget (content-draft (create "website" model (data json))) "at")))
      (ok (string= (at "{\"at\": \"2024-01-01T10:00:30.500Z\"}") "2024-01-01T10:00:00.000Z")
          "the seconds are dropped, as the editor gives none")
      (ok (string= (at "{\"at\": \"2024-01-01T19:05+09:00\"}") "2024-01-01T10:05:00.000Z")
          "and the zone it was given in becomes UTC")
      (ok (string= (at "{\"at\": \"2024-01-01T10:05:00.000Z\"}") "2024-01-01T10:05:00.000Z"))
      (dolist (value '("2024-01-01" "2024-01-01T10:00:00" "10:00:00"))
        (ok (signals (at (format nil "{\"at\": ~s}" value)) 'validation-error)
            (format nil "~s is no datetime, and is not made one" value))))
    (let* ((content (create "website" model (data "{\"at\": \"2024-01-01T10:05:00.000Z\"}")))
           (id (content-id content)))
      (testing "a change to the same minute is no change"
        (ok (eq (nth-value 1 (update-draft "website" model id (data "{\"at\": \"2024-01-01T10:05:59Z\"}")))
                :unchanged))
        (ok (= (count-revisions "website" id) 1)))
      (testing "a change and a publish keep it to the minute too"
        (update-draft "website" model id (data "{\"at\": \"2024-03-01T08:30:15+01:00\"}"))
        (ok (string= (jget (content-draft (get-content "website" id)) "at") "2024-03-01T07:30:00.000Z"))
        (publish "website" model id (data "{\"at\": \"2024-04-01T00:00:01Z\"}"))
        (ok (string= (jget (content-published (get-content "website" id)) "at") "2024-04-01T00:00:00.000Z"))))))

(deftest a-missing-boolean-and-false-are-the-same-draft
  (let ((id (content-id (make "{\"title\": \"Flag\"}" :publish t))))
    (ok (eq (nth-value 1 (update-draft "website" (blog) id (data "{\"featured\": false}"))) :unchanged)
        "false over a missing boolean changes nothing")
    (ok (eq (nth-value 1 (update-draft "website" (blog) id (data "{\"title\": \"Flag\", \"featured\": false}")
                                       :replace t))
            :unchanged)
        "nor does the editor's save, which always sends the key")
    (ok (string= (content-status (get-content "website" id)) "published"))
    (ok (= (count-revisions "website" id) 1))
    (testing "and a draft that comes back to the published data with false is dropped"
      (update-draft "website" (blog) id (data "{\"title\": \"Changed\"}"))
      (ok (eq (nth-value 1 (update-draft "website" (blog) id (data "{\"title\": \"Flag\", \"featured\": false}")
                                         :replace t))
              :published))
      (ok (string= (content-status (get-content "website" id)) "published"))))
  (let ((id (content-id (make "{\"title\": \"Off\", \"featured\": false}" :publish t))))
    (ok (eq (nth-value 1 (update-draft "website" (blog) id (data "{\"featured\": null}"))) :unchanged)
        "and null over false changes nothing either")
    (ok (eq (nth-value 1 (update-draft "website" (blog) id (data "{\"featured\": true}"))) :saved)
        "while true is a change")))

(deftest an-emptied-slug-that-comes-back-the-same-is-no-change
  (let* ((model (find-model "website" "page"))
         (id (content-id (create "website" model (data "{\"title\": \"Hello World\"}") :publish t))))
    (ok (string= (jget (content-published (get-content "website" id)) "slug") "hello-world"))
    (ok (eq (nth-value 1 (update-draft "website" model id (data "{\"title\": \"Hello World\"}") :replace t))
            :unchanged)
        "a save with the slug emptied makes the same slug again, and that is no change")
    (ok (eq (nth-value 1 (update-draft "website" model id (data "{\"slug\": \"\"}"))) :unchanged)
        "nor is a patch that blanks it")
    (ok (string= (content-status (get-content "website" id)) "published"))
    (ok (= (count-revisions "website" id) 1))))

(deftest system-timestamps-given-on-create-are-kept-in-utc
  (let ((c (make "{\"title\": \"Dated\"}" :publish t
                 :created-at "2024-01-01T10:00+09:00"
                 :updated-at "2024-01-02T03:04:05.5+01:00"
                 :published-at "2024-01-01T00:00:00Z"
                 :revised-at "2024-01-03T00:00:00.000Z")))
    (ok (string= (content-created-at c) "2024-01-01T01:00:00.000Z") "the zone it was given in becomes UTC")
    (ok (string= (content-updated-at c) "2024-01-02T02:04:05.500Z") "with milliseconds, as the server writes")
    (ok (string= (content-published-at c) "2024-01-01T00:00:00.000Z"))
    (ok (string= (content-revised-at c) "2024-01-03T00:00:00.000Z"))
    (ok (string= (content-created-at (get-content "website" (content-id c))) "2024-01-01T01:00:00.000Z")
        "and that is what is stored"))
  (testing "a timestamp needs a date, a time and a zone"
    (dolist (value '("10:00" "2024-01-01" "2024-01-01T10:00:00"))
      (ok (signals (make "{\"title\": \"Undated\"}" :created-at value) 'invalid-input)
          (format nil "~s is no point in time, and is not made one" value))))
  (testing "so the default order is the order in time"
    (make "{\"title\": \"Tokyo\"}" :publish t :published-at "2024-06-01T08:00:00+09:00")
    (make "{\"title\": \"UTC\"}" :publish t :published-at "2024-05-31T23:30:00Z")
    (ok (equal (titles (list-contents "website" "blog" (blog) (q)))
               '("UTC" "Tokyo" "Dated"))
        "half past eleven UTC is after eight in Tokyo the next morning")))

(deftest parse-query-defaults
  (let ((query (q)))
    (ok (= (query-limit query) 10))
    (ok (= (query-offset query) 0))
    (ok (null (query-include query)) "references stay ids by default")
    (ok (null (query-fields query))))
  (let ((query (q "limit" "500" "fields" "id,title" "include" "tags,author.avatar" "filters" "a[equals]1[and]b[exists][or]c[equals]2")))
    (ok (= (query-limit query) 100) "capped")
    (ok (equal (query-fields query) '("id" "title")))
    (ok (equal (query-include query) '(("tags") ("author" "avatar"))))
    (ok (equal (query-filters query) '((("a" "equals" "1") ("b" "exists" "")) (("c" "equals" "2")))))))

(deftest api-keys
  (multiple-value-bind (key id) (create-delivery-key "website" :label "site")
    (ok (string= (subseq key 0 5) "koya_"))
    (ok (string= (space-for-delivery-key key) "website"))
    (ng (space-for-delivery-key "koya_nope"))
    (ng (space-for-delivery-key nil))
    (ok (equal (mapcar #'key-label (list-delivery-keys "website")) '("site")))
    (delete-delivery-key "website" id)
    (ok (null (list-delivery-keys "website")))
    (ng (space-for-delivery-key key))))
