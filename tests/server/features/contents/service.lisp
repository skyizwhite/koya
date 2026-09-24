(defpackage #:koya-tests/server/features/contents/service
  (:use #:cl #:rove)
  (:import-from #:koya-server/db/connection #:connect-db #:disconnect-db)
  (:import-from #:koya-server/db/migrations #:migrate)
  (:import-from #:koya-server/db/schema-store #:save-schema #:create-space #:find-model)
  (:import-from #:koya-server/db/contents
                #:create-content #:save-draft #:publish-content #:unpublish-content
                #:delete-content #:get-content #:find-content #:list-contents #:ensure-draft-key
                #:find-object-content #:unique-value-taken-p)
  (:import-from #:koya-server/domain/content
                #:content-id #:content-status #:content-published #:content-draft
                #:content-published-at #:content-revised-at #:content-draft-key)
  (:import-from #:koya-server/db/contents #:discard-draft)
  (:import-from #:koya-server/domain/revision
                #:revision-id #:revision-event #:revision-data #:revision-by)
  (:import-from #:koya-server/db/content-revisions
                #:list-revisions #:count-revisions #:find-revision)
  (:import-from #:koya-server/db/connection #:fetch-one #:col)
  (:import-from #:koya-server/domain/query
                #:parse-query #:make-query #:query-limit #:query-offset #:query-orders
                #:query-filters #:query-fields #:query-include #:query-error)
  (:import-from #:koya-server/db/delivery-keys
                #:create-delivery-key #:list-delivery-keys #:delete-delivery-key #:space-for-delivery-key)
  (:import-from #:koya/core/schema #:make-field #:make-model #:make-schema)
  (:import-from #:koya/core/json #:parse-json #:jget))
(in-package #:koya-tests/server/features/contents/service)

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
  (save-schema "website"
               (make-schema :models (list (blog-model)
                                          (make-model "tag" :list (list (make-field :name :text)))
                                          (make-model "about" :object (list (make-field :body :richtext)))))))

(teardown (disconnect-db))

(defhook :before (koya-server/db/connection:exec "DELETE FROM contents"))

(defvar *read-eval-probe* nil "Set by a hostile filter value if the reader ever evaluates it.")

(defun data (json) (parse-json json))
(defun q (&rest kv) (parse-query (loop :for (k v) :on kv :by #'cddr :collect (cons k v))))
(defun titles (contents) (mapcar (lambda (c) (jget (content-published c) "title")) contents))

(deftest lifecycle
  (let ((c (create-content "website" "blog" (data "{\"title\": \"Draft one\"}"))))
    (ok (string= (content-status c) "draft"))
    (ok (null (content-published c)))
    (ok (string= (jget (content-draft c) "title") "Draft one"))
    (ok (null (content-published-at c)))
    (let ((p (publish-content (content-id c))))
      (ok (string= (content-status p) "published"))
      (ok (string= (jget (content-published p) "title") "Draft one"))
      (ok (null (content-draft p)))
      (ok (content-published-at p))
      (let ((d (save-draft (content-id c) (data "{\"title\": \"Edited\"}"))))
        (ok (string= (content-status d) "published+draft"))
        (ok (string= (jget (content-published d) "title") "Draft one") "published untouched by a draft save")
        (ok (string= (jget (content-draft d) "title") "Edited"))
        (let ((p2 (publish-content (content-id c))))
          (ok (string= (jget (content-published p2) "title") "Edited") "publish promotes the draft")
          (ok (string= (content-published-at p2) (content-published-at p)) "first publish date is kept")
          (ok (string>= (content-revised-at p2) (content-revised-at p)))
          (let ((u (unpublish-content (content-id c))))
            (ok (string= (content-status u) "draft"))
            (ok (null (content-published u)))
            (ok (string= (jget (content-draft u) "title") "Edited") "unpublish keeps the data as draft"))))
      (delete-content (content-id c))
      (ng (get-content (content-id c))))))

(deftest every-write-leaves-a-revision
  (let* ((c (create-content "website" "blog" (data "{\"title\": \"One\"}") :by "owner"))
         (id (content-id c)))
    (save-draft id (data "{\"title\": \"Two\"}") :by "key:ci")
    (save-draft id (data "{\"title\": \"Two\"}"))
    (publish-content id)
    (save-draft id (data "{\"title\": \"Three\"}"))
    (discard-draft id)
    (unpublish-content id)
    (let ((revisions (list-revisions id)))
      (ok (equal (mapcar #'revision-event revisions) '("unpublish" "discard" "draft" "publish" "draft" "draft"))
          "newest first; the second save of the same data is not an event")
      (ok (equal (mapcar (lambda (r) (jget (revision-data r) "title")) revisions)
                 '("Two" "Two" "Three" "Two" "Two" "One"))
          "each holds what the write left the content with")
      (ok (equal (mapcar #'revision-by (last revisions 2)) '("key:ci" "owner")))
      (ok (string= (revision-by (first revisions)) "") "a write that names nobody stores nobody"))
    (testing "the published ones are the versions that were live"
      (ok (= (count-revisions id :published-only t) 1))
      (ok (equal (mapcar #'revision-event (list-revisions id :published-only t)) '("publish"))))
    (testing "what changes nothing that was live is not an event"
      (let* ((draft (create-content "website" "blog" (data "{\"title\": \"Never live\"}")))
             (live (create-content "website" "blog" (data "{\"title\": \"Live\"}") :publish t)))
        (unpublish-content (content-id draft))
        (ok (equal (mapcar #'revision-event (list-revisions (content-id draft))) '("draft"))
            "unpublishing a content that was never published")
        (discard-draft (content-id live))
        (ok (equal (mapcar #'revision-event (list-revisions (content-id live))) '("publish"))
            "discarding a draft that is not there")))
    (testing "a revision belongs to its content"
      (let ((other (create-content "website" "blog" (data "{\"title\": \"Other\"}"))))
        (ng (find-revision (content-id other) (revision-id (first (list-revisions id)))))))
    (testing "deleting the content deletes its history"
      (delete-content id)
      (ok (zerop (col (fetch-one "SELECT COUNT(*) AS n FROM content_revisions WHERE content_id = ?" id) "n"))))))

(deftest draft-keys
  (let* ((c (create-content "website" "blog" (data "{\"title\": \"x\"}")))
         (key (content-draft-key c)))
    (ok (= (length key) 32) "a draft gets a key on creation")
    (ok (string= key (ensure-draft-key (content-id c))) "ensure returns the current key")
    (let ((saved (save-draft (content-id c) (data "{\"title\": \"y\"}"))))
      (ok (string/= (content-draft-key saved) key) "every draft save rotates the key")
      (ok (null (content-draft-key (publish-content (content-id c)))) "publishing clears it")
      (ok (content-draft-key (unpublish-content (content-id c))) "unpublishing issues a new one"))
    (let ((p (create-content "website" "blog" (data "{\"title\": \"pub\"}") :publish t)))
      (ok (null (content-draft-key p)) "published content has no key")
      (ok (= (length (ensure-draft-key (content-id p))) 32) "but one can be generated on demand"))))

(deftest object-content
  (ng (find-object-content "website" "about"))
  (create-content "website" "about" (data "{\"body\": \"hi\"}") :publish t)
  (ok (string= (jget (content-published (find-object-content "website" "about")) "body") "hi")))

(deftest uniqueness
  (let ((c (create-content "website" "blog" (data "{\"title\": \"Taken\"}") :publish t)))
    (ok (unique-value-taken-p "website" "blog" "title" "Taken"))
    (ng (unique-value-taken-p "website" "blog" "title" "Taken" :exclude-id (content-id c)) "the content itself does not count")
    (ng (unique-value-taken-p "website" "blog" "title" "Free"))
    (save-draft (content-id (create-content "website" "blog" (data "{\"title\": \"z\"}"))) (data "{\"title\": \"In draft\"}"))
    (ok (unique-value-taken-p "website" "blog" "title" "In draft") "drafts count too")))

(deftest listing
  (create-content "website" "blog" (data "{\"title\": \"Alpha\", \"count\": 1, \"featured\": true, \"tags\": [\"01ARZ3NDEKTSV4RRFFQ69G5FAV\"], \"day\": \"2026-01-01\"}") :publish t)
  (create-content "website" "blog" (data "{\"title\": \"Beta\", \"count\": 5, \"featured\": false, \"tags\": [], \"day\": \"2026-02-01\"}") :publish t)
  (create-content "website" "blog" (data "{\"title\": \"Gamma\", \"count\": 10, \"day\": \"2026-03-01\"}") :publish t)
  (create-content "website" "blog" (data "{\"title\": \"Hidden draft\"}"))
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
        (ok (equal (titles contents) '("Beta")))))
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
      (ok (equal (titles (list-contents "website" "blog" model (q "filters" "featured[exists]"))) '("Beta" "Alpha")))
      (ok (equal (titles (list-contents "website" "blog" model (q "filters" "featured[not_exists]"))) '("Gamma")))
      (ok (equal (titles (list-contents "website" "blog" model (q "filters" "tags[contains]01ARZ3NDEKTSV4RRFFQ69G5FAV"))) '("Alpha")))
      (ok (equal (titles (list-contents "website" "blog" model (q "filters" "day[greater_than]2026-01-15[and]count[less_than]10"))) '("Beta")))
      (ok (equal (titles (list-contents "website" "blog" model (q "filters" "title[not_equals]Beta"))) '("Gamma" "Alpha"))))
    (testing "bad queries are rejected"
      (ok (signals (list-contents "website" "blog" model (q "filters" "nope[equals]1")) 'query-error))
      (ok (signals (list-contents "website" "blog" model (q "filters" "count[equals]abc")) 'query-error))
      (ok (signals (list-contents "website" "blog" model (q "filters" "count[equals]1 2")) 'query-error) "trailing garbage")
      (let ((*read-eval-probe* nil))
        (ok (signals (list-contents "website" "blog" model
                                    (q "filters" "count[equals]#.(setf koya-tests/server/features/contents/service::*read-eval-probe* t)"))
                     'query-error)
            "reader macros in a number filter are rejected")
        (ok (null *read-eval-probe*) "and never evaluated"))
      (ok (signals (list-contents "website" "blog" model (q "filters" "title[weird]1")) 'query-error))
      (ok (signals (list-contents "website" "blog" model (q "orders" "nope")) 'query-error))
      (ok (signals (q "limit" "abc") 'query-error)))))

(deftest listing-without-a-limit
  (dotimes (i 12)
    (create-content "website" "blog" (data (format nil "{\"title\": \"Post ~a\"}" i))))
  (let ((model (find-model "website" "blog")))
    (multiple-value-bind (contents total) (list-contents "website" "blog" model (make-query :limit nil) :status :all)
      (ok (= total 12))
      (ok (= (length contents) 12) "a query whose limit is NIL lists every row"))
    (ok (= (length (list-contents "website" "blog" model (make-query) :status :all)) 10)
        "one made without a limit keeps the default")))

(deftest listing-by-status
  (create-content "website" "blog" (data "{\"title\": \"Live\"}") :publish t)
  (let ((both (create-content "website" "blog" (data "{\"title\": \"Live with a draft\"}") :publish t)))
    (save-draft (content-id both) (data "{\"title\": \"Live with a draft\", \"count\": 1}")))
  (create-content "website" "blog" (data "{\"title\": \"Only a draft\"}"))
  (let ((model (find-model "website" "blog")))
    (flet ((titles-with (status)
             ;; the draft's title when there is one, as the admin list shows it
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
    (ok (equal (mapcar (lambda (k) (getf k :label)) (list-delivery-keys "website")) '("site")))
    (delete-delivery-key "website" id)
    (ok (null (list-delivery-keys "website")))
    (ng (space-for-delivery-key key))))
