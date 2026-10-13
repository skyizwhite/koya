(defpackage #:koya-spec/server/usecases/contents
  (:use #:cl #:rove)
  (:import-from #:koya-spec/server/stored #:stored-content)
  (:import-from #:koya-server/domain/errors #:conflict #:invalid-input #:not-found #:koya-error-code)
  (:import-from #:koya-server/domain/key #:key-label)
  (:import-from #:koya-server/usecases/schema #:replace-schema)
  (:import-from #:koya-spec/server/schema #:with-schema)
  (:import-from #:koya-server/infra/db/connection
                #:connect-db #:disconnect-db #:fetch-one #:col #:exec)
  (:import-from #:koya-server/infra/db/migrations #:migrate)
  (:import-from #:koya-server/usecases/ports/spaces #:find-model)
  (:import-from #:koya-server/usecases/spaces #:create-space)
  (:import-from #:koya-server/usecases/ports/contents
                #:list-contents #:model-contents #:space-contents
                #:find-object-content #:unique-value-taken-p #:list-revisions
                #:count-revisions #:find-revision)
  (:import-from #:koya-server/usecases/contents
                #:create #:update-draft #:publish #:unpublish #:discard #:destroy #:draft-key
                #:object-content #:update-object #:publish-object #:content-references #:content-by-slug
                #:apply-to-each)
  (:import-from #:koya-spec/server/reads #:reads-of)
  (:import-from #:koya-server/usecases/actor #:*actor*)
  (:import-from #:koya-server/domain/content
                #:content-id #:content-status #:content-published #:content-draft
                #:content-published-p #:content-draft-p
                #:content-published-at #:content-revised-at #:content-draft-key
                #:content-created-at #:content-updated-at)
  (:import-from #:koya-server/domain/revision
                #:revision-id #:revision-event #:revision-data #:revision-by)
  (:import-from #:koya-server/usecases/keys
                #:create-delivery-key #:list-delivery-keys #:delete-delivery-key
                #:space-for-delivery-key)
  (:import-from #:koya-server/domain/query
                #:parse-query #:make-query #:query-limit #:query-offset #:query-orders
                #:query-filters #:query-fields #:query-include #:query-search #:query-error)
  (:import-from #:koya-core/validate #:validation-error)
  (:import-from #:koya-core/schema #:make-field #:make-model #:make-schema #:model-name #:make-custom-field)
  (:import-from #:access #:access #:accesses)
  (:import-from #:koya-spec/server/domain/id #:with-drawn-ids))
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
                                                                         (make-field :slug :slug)))
                                          (make-model "about" :object (list (make-field :body :richtext)))))))

(teardown (disconnect-db))

(defhook :before (exec "DELETE FROM contents"))

(deftest a-bulk-action-reads-each-content-once
  (let* ((draft (content-id (make (list :title "Draft"))))
         (live (content-id (make (list :title "Live") :publish t)))
         (also (content-id (make (list :title "Also live") :publish t)))
         (ids (list draft live also)))
    (let ((reads (reads-of (lambda ()
                             (ok (equal (multiple-value-list (apply-to-each "website" (blog) ids "publish")) '(1 2 0 nil))
                                 "publishing a selection publishes the draft and skips what is published")))))
      (ok (equal reads '("FIND-CONTENT" "FIND-CONTENT" "FIND-CONTENT"))
          "reading each content once, where it is changed"))
    (ok (equal (reads-of (lambda () (apply-to-each "website" (blog) (list draft "gone") "delete")))
               '("FIND-CONTENT" "FIND-CONTENT"))
        "and so does deleting")
    (ok (equal (multiple-value-list (apply-to-each "website" (blog) (list live "gone") "unpublish"))
               '(1 0 1 "Content gone does not exist"))
        "a content that is gone fails, and the rest go on")
    (ok (equal (multiple-value-list (apply-to-each "website" (blog) (list live also) "unpublish")) '(1 1 0 nil))
        "unpublishing skips a draft")))

(deftest a-key-no-field-has-is-refused-first
  (let ((id (content-id (make (list :title "Kept")))))
    (ok (signals (update-draft "website" (blog) id (list :title "Changed" :feautred :null) :replace t) 'validation-error)
        "a key no field has is refused, null or not")
    (ok (signals (update-draft "website" (blog) id (list :title "Kept" :feautred :null) :replace t) 'validation-error)
        "even when the rest is as it is")
    (ok (signals (update-draft "website" (blog) id (list :feautred :null)) 'validation-error)
        "and in a patch, where a null would take a field's value away")
    (ok (equal (content-draft (update-draft "website" (blog) id (list :title "Changed" :body :null) :replace t))
               '(:title "Changed"))
        "while a field given null is saved as no value")
    (ok (eq (nth-value 1 (update-draft "website" (blog) id (list :title "Changed" :featured :null) :replace t)) :unchanged)
        "and a boolean given null is false, as it is when left out")))

(defvar *read-eval-probe* nil)

(defun blog () (find-model "website" "blog"))
(defun make (data &rest args)
  (apply #'create "website" (blog) data args))
(defun q (&rest kv) (parse-query (loop :for (k v) :on kv :by #'cddr :collect (cons k v))))
(defun titles (contents) (mapcar (lambda (c) (access (content-published c) :title)) contents))

(deftest an-id-koya-makes-is-twelve-letters-and-digits
  (let ((ids (loop :for n :below 20 :collect (content-id (make (list :title (format nil "T~a" n)))))))
    (ok (every (lambda (id) (cl-ppcre:scan "^[a-z0-9]{12}\\z" id)) ids) "lowercase letters and digits, twelve of them")
    (ok (= (length (remove-duplicates ids :test #'string=)) 20) "drawn afresh for each content")))

(deftest a-taken-id-is-drawn-again
  (let ((taken (content-id (make (list :title "First")))))
    (ok (string= (content-id (with-drawn-ids (list taken "zzzzzzzzzzzz") (lambda () (make (list :title "Second")))))
                 "zzzzzzzzzzzz"))
    (ok (string= (access (content-draft (stored-content "website" taken)) :title) "First") "and the content that holds it is untouched")))

(deftest contents-made-at-once-are-written-out-in-the-order-they-were-made
  (with-drawn-ids (list "zzzzzzzzzzzz" "aaaaaaaaaaaa")
    (lambda ()
      (make (list :title "Earlier") :created-at "2026-01-01T00:00:00.000Z")
      (make (list :title "Later") :created-at "2026-01-01T00:00:00.000Z")))
  (ok (equal (mapcar #'content-id (model-contents "website" "blog")) '("zzzzzzzzzzzz" "aaaaaaaaaaaa")))
  (ok (equal (mapcar #'content-id (space-contents "website")) '("zzzzzzzzzzzz" "aaaaaaaaaaaa"))
      "not in the order of their ids"))

(deftest lifecycle
  (let ((c (make (list :title "Draft one"))))
    (ok (string= (content-status c) "draft"))
    (ng (content-published-p c))
    (ok (string= (access (content-draft c) :title) "Draft one"))
    (ok (null (content-published-at c)))
    (let ((p (publish "website" (blog) (content-id c))))
      (ok (string= (content-status p) "published"))
      (ok (string= (access (content-published p) :title) "Draft one"))
      (ng (content-draft-p p))
      (ok (content-published-at p))
      (let ((d (update-draft "website" (blog) (content-id c) (list :title "Edited"))))
        (ok (string= (content-status d) "published+draft"))
        (ok (string= (access (content-published d) :title) "Draft one") "published untouched by a draft save")
        (ok (string= (access (content-draft d) :title) "Edited"))
        (let ((p2 (publish "website" (blog) (content-id c))))
          (ok (string= (access (content-published p2) :title) "Edited") "publish promotes the draft")
          (ok (string= (content-published-at p2) (content-published-at p)) "first publish date is kept")
          (ok (string>= (content-revised-at p2) (content-revised-at p)))
          (let ((u (unpublish "website" (blog) (content-id c))))
            (ok (string= (content-status u) "draft"))
            (ng (content-published-p u))
            (ok (null (content-published-at u)) "an unpublished content has no publish date")
            (ok (null (content-revised-at u)) "nor a revision date")
            (ok (string= (access (content-draft u) :title) "Edited") "unpublish keeps the data as draft")
            (ok (string= (content-status (stored-content "website" (content-id c))) "draft") "and that is what is stored"))))
      (destroy "website" (blog) (content-id c))
      (ng (stored-content "website" (content-id c))))))

(deftest every-write-leaves-a-revision
  (let* ((c (let ((*actor* "owner")) (make (list :title "One"))))
         (id (content-id c)))
    (let ((*actor* "key:ci")) (update-draft "website" (blog) id (list :title "Two")))
    (update-draft "website" (blog) id (list :title "Two"))
    (publish "website" (blog) id)
    (update-draft "website" (blog) id (list :title "Three"))
    (discard "website" (blog) id)
    (unpublish "website" (blog) id)
    (let ((revisions (list-revisions "website" id)))
      (ok (equal (mapcar #'revision-event revisions) '("unpublish" "discard" "draft" "publish" "draft" "draft"))
          "newest first; the second save of the same data is not an event")
      (ok (equal (mapcar (lambda (r) (access (revision-data r) :title)) revisions)
                 '("Two" "Two" "Three" "Two" "Two" "One"))
          "each holds what the write left the content with")
      (ok (equal (mapcar #'revision-by (last revisions 2)) '("key:ci" "owner")))
      (ok (string= (revision-by (first revisions)) "") "a write that names nobody stores nobody"))
    (testing "the published ones are the versions that were live"
      (ok (= (count-revisions "website" id :published-only t) 1))
      (ok (equal (mapcar #'revision-event (list-revisions "website" id :published-only t)) '("publish"))))
    (testing "what changes nothing that was live is not an event"
      (let ((draft (make (list :title "Never live")))
            (live (make (list :title "Live") :publish t)))
        (ok (signals (unpublish "website" (blog) (content-id draft)) 'conflict)
            "a content that was never published cannot be unpublished")
        (ok (equal (mapcar #'revision-event (list-revisions "website" (content-id draft))) '("draft")) "and nothing is kept")
        (ok (signals (discard "website" (blog) (content-id draft)) 'conflict)
            "a content that was never published has no draft to discard, only itself")
        (ok (signals (discard "website" (blog) (content-id live)) 'conflict)
            "a published content with no draft has none to discard")
        (ok (equal (mapcar #'revision-event (list-revisions "website" (content-id live))) '("publish")) "and nothing is kept")))
    (testing "a revision belongs to its content"
      (let ((other (make (list :title "Other"))))
        (ng (find-revision "website" (content-id other) (revision-id (first (list-revisions "website" id)))))))
    (testing "deleting the content deletes its history"
      (destroy "website" (blog) id)
      (ok (zerop (col (fetch-one "SELECT COUNT(*) AS n FROM content_revisions WHERE content_id = ?" id) "n"))))))

(deftest draft-keys
  (let* ((c (make (list :title "x")))
         (key (content-draft-key c)))
    (ok (= (length key) 32) "a draft gets a key on creation")
    (ok (string= key (draft-key "website" (blog) (content-id c))) "asking for it returns the current key")
    (let ((saved (update-draft "website" (blog) (content-id c) (list :title "y"))))
      (ok (string/= (content-draft-key saved) key) "every draft save rotates the key")
      (ok (null (content-draft-key (publish "website" (blog) (content-id c)))) "publishing clears it")
      (ok (content-draft-key (unpublish "website" (blog) (content-id c))) "unpublishing issues a new one"))
    (let ((p (make (list :title "pub") :publish t)))
      (ok (null (content-draft-key p)) "published content has no key")
      (let ((made (draft-key "website" (blog) (content-id p))))
        (ok (= (length made) 32) "but one can be made on demand")
        (ok (string= made (content-draft-key (stored-content "website" (content-id p)))) "and is kept")))))

(deftest object-content
  (ng (find-object-content "website" "about"))
  (create "website" (find-model "website" "about") (list :body "hi") :publish t)
  (ok (string= (access (content-published (find-object-content "website" "about")) :body) "hi")))

(deftest an-object-is-written-through-its-model
  (let ((about (find-model "website" "about")))
    (testing "before its first write it has no content to read"
      (ok (signals (object-content "website" about) 'not-found)))
    (testing "the first save makes its content, as a draft"
      (let ((saved (update-object "website" about (list :body "draft"))))
        (ok (string= (content-status saved) "draft"))
        (ok (string= (content-id saved) (content-id (object-content "website" about))))))
    (testing "a later save merges onto that content"
      (let ((id (content-id (object-content "website" about))))
        (update-object "website" about nil)
        (ok (string= (access (content-draft (object-content "website" about)) :body) "draft"))
        (ok (string= (content-id (object-content "website" about)) id) "and makes no second")))
    (testing "publishing publishes the draft, or the data given"
      (ok (string= (access (content-published (publish-object "website" about)) :body) "draft"))
      (ok (string= (access (content-published (publish-object "website" about :data (list :body "given"))) :body)
                   "given"))))
  (testing "a first write can publish at once"
    (exec "DELETE FROM contents")
    (let ((about (find-model "website" "about")))
      (ok (signals (publish-object "website" about) 'not-found) "though not with no data at all")
      (ok (string= (content-status (publish-object "website" about :data (list :body "live"))) "published")))))

(deftest an-object-content-is-not-deleted
  (let* ((about (find-model "website" "about"))
         (content (update-object "website" about (list :body "stays")))
         (e (handler-case (destroy "website" about (content-id content)) (conflict (e) e))))
    (ok (string= (koya-error-code e) "object_stays") "it goes only with its model")
    (ok (object-content "website" about))))

(deftest a-content-knows-what-refers-to-it
  (let* ((tag (content-id (create "website" (find-model "website" "tag") (list :name "lisp"))))
         (a (content-id (make (list :title "A" :tags (vector tag)))))
         (b (content-id (make (list :title "B" :tags (vector tag)) :publish t))))
    (make (list :title "C"))
    (let ((references (content-references "website" "tag" tag)))
      (ok (equal (sort (mapcar (lambda (r) (getf r :id)) references) #'string<) (sort (list a b) #'string<))
          "the contents that refer to it, draft or published, and no other")
      (ok (every (lambda (r) (string= (model-name (getf r :model)) "blog")) references) "each with its model")
      (ok (every (lambda (r) (string= (getf r :label) (getf r :id))) references)
          "and its label, which is its id when its model names none"))
    (ok (null (content-references "website" "blog" a)) "nothing refers to a content no field can point at")))

(deftest uniqueness
  (let ((c (make (list :title "Taken") :publish t)))
    (ok (unique-value-taken-p "website" "blog" "title" "Taken"))
    (ng (unique-value-taken-p "website" "blog" "title" "Taken" :exclude-id (content-id c)) "the content itself does not count")
    (ng (unique-value-taken-p "website" "blog" "title" "Free"))
    (update-draft "website" (blog) (content-id (make (list :title "z"))) (list :title "In draft"))
    (ok (unique-value-taken-p "website" "blog" "title" "In draft") "drafts count too")))

(deftest listing
  (make (list :title "Alpha" :count 1 :featured t :tags (vector "01ARZ3NDEKTSV4RRFFQ69G5FAV") :day "2026-01-01") :publish t)
  (make (list :title "Beta" :count 5 :featured nil :tags (vector) :day "2026-02-01") :publish t)
  (make (list :title "Gamma" :count 10 :day "2026-03-01") :publish t)
  (make (list :title "Hidden draft"))
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
    (make (list :title (format nil "Post ~a" i))))
  (let ((model (find-model "website" "blog")))
    (multiple-value-bind (contents total) (list-contents "website" "blog" model (make-query :limit nil) :status :all)
      (ok (= total 12))
      (ok (= (length contents) 12) "a query whose limit is NIL lists every row"))
    (ok (= (length (list-contents "website" "blog" model (make-query) :status :all)) 10)
        "one made without a limit keeps the default")))

(deftest listing-by-status
  (make (list :title "Live") :publish t)
  (let ((both (make (list :title "Live with a draft") :publish t)))
    (update-draft "website" (blog) (content-id both) (list :title "Live with a draft" :count 1)))
  (make (list :title "Only a draft"))
  (let ((model (find-model "website" "blog")))
    (flet ((titles-with (status)
             (sort (mapcar (lambda (c) (access (or (content-draft c) (content-published c)) :title))
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
  (make (list :title "True" :featured t :body "<p>x</p>" :tags (vector "01ARZ3NDEKTSV4RRFFQ69G5FAV") :count 0) :publish t)
  (make (list :title "False" :featured nil :body (format nil " ~c~% " #\Tab) :tags (vector)) :publish t)
  (make (list :title "Missing") :publish t)
  (make (list :title "Null" :featured :null :body :null :tags :null :count :null) :publish t)
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
    (flet ((at (data) (access (content-draft (create "website" model data)) :at)))
      (ok (string= (at (list :at "2024-01-01T10:00:30.500Z")) "2024-01-01T10:00:00.000Z")
          "the seconds are dropped, as the editor gives none")
      (ok (string= (at (list :at "2024-01-01T19:05+09:00")) "2024-01-01T10:05:00.000Z")
          "and the zone it was given in becomes UTC")
      (ok (string= (at (list :at "2024-01-01T10:05:00.000Z")) "2024-01-01T10:05:00.000Z"))
      (dolist (value '("2024-01-01" "2024-01-01T10:00:00" "10:00:00"))
        (ok (signals (at (list :at value)) 'validation-error)
            (format nil "~s is no datetime, and is not made one" value))))
    (let* ((content (create "website" model (list :at "2024-01-01T10:05:00.000Z")))
           (id (content-id content)))
      (testing "a change to the same minute is no change"
        (ok (eq (nth-value 1 (update-draft "website" model id (list :at "2024-01-01T10:05:59Z")))
                :unchanged))
        (ok (= (count-revisions "website" id) 1)))
      (testing "a change and a publish keep it to the minute too"
        (update-draft "website" model id (list :at "2024-03-01T08:30:15+01:00"))
        (ok (string= (access (content-draft (stored-content "website" id)) :at) "2024-03-01T07:30:00.000Z"))
        (publish "website" model id :data (list :at "2024-04-01T00:00:01Z"))
        (ok (string= (access (content-published (stored-content "website" id)) :at) "2024-04-01T00:00:00.000Z"))))))

(deftest a-missing-boolean-and-false-are-the-same-draft
  (let ((id (content-id (make (list :title "Flag") :publish t))))
    (ok (eq (nth-value 1 (update-draft "website" (blog) id (list :featured nil))) :unchanged)
        "false over a missing boolean changes nothing")
    (ok (eq (nth-value 1 (update-draft "website" (blog) id (list :title "Flag" :featured nil)
                                       :replace t))
            :unchanged)
        "nor does the editor's save, which always sends the key")
    (ok (string= (content-status (stored-content "website" id)) "published"))
    (ok (= (count-revisions "website" id) 1))
    (testing "and a draft that comes back to the published data with false is dropped"
      (update-draft "website" (blog) id (list :title "Changed"))
      (ok (eq (nth-value 1 (update-draft "website" (blog) id (list :title "Flag" :featured nil)
                                         :replace t))
              :published))
      (ok (string= (content-status (stored-content "website" id)) "published"))))
  (let ((id (content-id (make (list :title "Off" :featured nil) :publish t))))
    (ok (eq (nth-value 1 (update-draft "website" (blog) id (list :featured :null))) :unchanged)
        "and null over false changes nothing either")
    (ok (eq (nth-value 1 (update-draft "website" (blog) id (list :featured t))) :saved)
        "while true is a change")))

(deftest a-draft-emptied-stays-a-draft
  (let* ((tag (find-model "website" "tag"))
         (id (content-id (create "website" tag (list :name "x")))))
    (ok (eq (nth-value 1 (update-draft "website" tag id (list :name :null))) :saved)
        "a draft saved with no values is saved as one, though it has no published data to match")
    (let ((content (stored-content "website" id)))
      (ok (string= (content-status content) "draft") "and is not published")
      (ok (null (content-draft content)) "holding no values"))))

(deftest a-blank-slug-stays-blank
  (let ((id (content-id (create "website" (find-model "website" "page") (list :title "Hello World") :publish t))))
    (ng (nth-value 1 (access (content-published (stored-content "website" id)) :slug))
        "nothing makes a slug from the title")))

(deftest a-slug-is-unique-without-saying-so
  (let* ((model (find-model "website" "page"))
         (live (content-id (create "website" model (list :title "Live" :slug "live") :publish t)))
         (drafted (content-id (create "website" model (list :title "Drafted" :slug "drafted")))))
    (ok (signals (create "website" model (list :slug "live")) 'validation-error)
        "against another content's published slug")
    (ok (signals (create "website" model (list :slug "drafted")) 'validation-error)
        "and against its draft's")
    (update-draft "website" model live (list :slug "live-next"))
    (ok (signals (update-draft "website" model drafted (list :slug "live")) 'validation-error)
        "a published slug a draft moves away from is still taken until the move is published")
    (ok (create "website" model (list :title "One")) "a blank slug is not a value")
    (ok (create "website" model (list :title "Two")) "so two blanks are no clash")))

(deftest a-content-is-found-by-its-slug
  (let* ((model (find-model "website" "page"))
         (live (content-id (create "website" model (list :title "Live" :slug "live") :publish t)))
         (drafted (content-id (create "website" model (list :title "Drafted" :slug "drafted")))))
    (update-draft "website" model live (list :slug "live-next"))
    (ok (string= (content-id (content-by-slug "website" "page" "live")) live) "by its published slug")
    (ok (string= (content-id (content-by-slug "website" "page" "live-next")) live) "by its draft's")
    (ok (string= (content-id (content-by-slug "website" "page" "drafted")) drafted) "a content that is only a draft too")
    (ok (signals (content-by-slug "website" "page" "nope") 'not-found))
    (ok (signals (content-by-slug "website" "tag" "live") 'not-found) "only in its own model")))

(deftest system-timestamps-given-on-create-are-kept-in-utc
  (let ((c (make (list :title "Dated") :publish t
                 :created-at "2024-01-01T10:00+09:00"
                 :updated-at "2024-01-02T03:04:05.5+01:00"
                 :published-at "2024-01-01T00:00:00Z"
                 :revised-at "2024-01-03T00:00:00.000Z")))
    (ok (string= (content-created-at c) "2024-01-01T01:00:00.000Z") "the zone it was given in becomes UTC")
    (ok (string= (content-updated-at c) "2024-01-02T02:04:05.500Z") "with milliseconds, as the server writes")
    (ok (string= (content-published-at c) "2024-01-01T00:00:00.000Z"))
    (ok (string= (content-revised-at c) "2024-01-03T00:00:00.000Z"))
    (ok (string= (content-created-at (stored-content "website" (content-id c))) "2024-01-01T01:00:00.000Z")
        "and that is what is stored"))
  (testing "a timestamp needs a date, a time and a zone"
    (dolist (value '("10:00" "2024-01-01" "2024-01-01T10:00:00"))
      (ok (signals (make (list :title "Undated") :created-at value) 'invalid-input)
          (format nil "~s is no point in time, and is not made one" value))))
  (testing "so the default order is the order in time"
    (make (list :title "Tokyo") :publish t :published-at "2024-06-01T08:00:00+09:00")
    (make (list :title "UTC") :publish t :published-at "2024-05-31T23:30:00Z")
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

(deftest a-query-param-that-is-not-a-string-is-none
  (let ((query (parse-query (list (cons "limit" 5) (cons "orders" 1) (cons "filters" (list "a"))
                                  (cons "fields" 1) (cons "include" 1) (cons "q" 1)))))
    (ok (= (query-limit query) 10) "a limit that is not text is the default")
    (ok (null (query-orders query)) "and so are the rest")
    (ok (null (query-filters query)))
    (ok (null (query-fields query)))
    (ok (null (query-include query)))
    (ok (null (query-search query)))))

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

(deftest inside-a-custom-field
  (with-schema ("website"
                (make-schema :custom-fields (list (make-custom-field "card" (list (make-field :link :reference :model "tag")
                                                                                  (make-field :shown :boolean)
                                                                                  (make-field :at :datetime)
                                                                                  (make-field :pinned :boolean :default t)
                                                                                  (make-field :note :text))))
                             :models (list (blog-model)
                                           (make-model "tag" :list (list (make-field :name :text)))
                                           (make-model "event" :list (list (make-field :at :datetime)))
                                           (make-model "page" :list (list (make-field :title :text)
                                                                          (make-field :card :custom :custom-field "card")))
                                           (make-model "about" :object (list (make-field :body :richtext))))))
    (let* ((page (find-model "website" "page"))
           (tag (content-id (create "website" (find-model "website" "tag") (list :name "x") :publish t)))
           (content (create "website" page
                            (list :title "P" :card (list :link tag :at "2026-09-20T10:00:59+09:00"))
                            :publish t)))
      (testing "a datetime inside is kept to the minute in UTC"
        (ok (string= (accesses (content-published content) :card :at) "2026-09-20T01:00:00.000Z")))
      (testing "a boolean inside starts as its default says"
        (ok (eq (accesses (content-published content) :card :pinned) t))
        (ok (null (nth-value 1 (access (access (content-published
                                                (create "website" page (list :title "N" :card (list :at "2026-09-20T01:00:00.000Z" :pinned :null))
                                                        :publish t))
                                               :card)
                                       :pinned)))
            "unless it is given null, which is false"))
      (testing "a reference inside is a use"
        (ok (equal (mapcar (lambda (r) (getf r :id)) (content-references "website" "tag" tag)) (list (content-id content))))
        (ok (signals (unpublish "website" (find-model "website" "tag") tag) 'conflict)))
      (testing "a boolean missing inside and one that is false are the same"
        (ok (eq :unchanged (nth-value 1 (update-draft "website" page (content-id content)
                                                      (list :title "P" :card (list :link tag :at "2026-09-20T01:00:00.000Z"
                                                                                   :shown nil :pinned t))
                                                      :replace t)))))
      (flet ((card (&rest more) (list* :link tag :at "2026-09-20T01:00:00.000Z" :pinned t more)))
        (testing "a null inside, for a field that has no value, changes nothing"
          (ok (eq :unchanged (nth-value 1 (update-draft "website" page (content-id content) (list :card (card :note :null))))))
          (ok (eq :saved (nth-value 1 (update-draft "website" page (content-id content) (list :title "Q"))))
              "a draft that differs from the published data is kept")
          (ok (eq :published (nth-value 1 (update-draft "website" page (content-id content)
                                                        (list :title "P" :card (card :note :null)))))
              "and one back to the published data with such a null is dropped"))
        (testing "a key the custom field does not have is refused, null or not"
          (ok (signals (update-draft "website" page (content-id content) (list :card (card :bogus :null)))
                       'validation-error)))))))

(deftest inside-a-repeater
  (with-schema ("website"
                (make-schema :custom-fields (list (make-custom-field "card" (list (make-field :link :reference :model "tag")
                                                                                  (make-field :shown :boolean)
                                                                                  (make-field :at :datetime)
                                                                                  (make-field :pinned :boolean :default t)
                                                                                  (make-field :note :text))))
                             :models (list (blog-model)
                                           (make-model "tag" :list (list (make-field :name :text)))
                                           (make-model "event" :list (list (make-field :at :datetime)))
                                           (make-model "page" :list (list (make-field :title :text)
                                                                          (make-field :cards :repeater :custom-fields '(card))))
                                           (make-model "about" :object (list (make-field :body :richtext))))))
    (let* ((page (find-model "website" "page"))
           (tag (content-id (create "website" (find-model "website" "tag") (list :name "x") :publish t)))
           (content (create "website" page
                            (list :title "P" :cards (vector (list :field-id "card" :link tag :at "2026-09-20T10:00:59+09:00")))
                            :publish t)))
      (testing "a datetime in a row is kept to the minute in UTC"
        (ok (string= (access (aref (access (content-published content) :cards) 0) :at) "2026-09-20T01:00:00.000Z")))
      (testing "a boolean in a row starts as its default says"
        (ok (eq (access (aref (access (content-published content) :cards) 0) :pinned) t))
        (ok (null (nth-value 1 (access (aref (access (content-published
                                                      (create "website" page
                                                              (list :title "N" :cards (vector (list :field-id "card" :pinned :null)))
                                                              :publish t))
                                                     :cards)
                                             0)
                                       :pinned)))
            "unless it is given null, which is false"))
      (testing "a reference in a row is a use"
        (ok (equal (mapcar (lambda (r) (getf r :id)) (content-references "website" "tag" tag)) (list (content-id content))))
        (ok (signals (unpublish "website" (find-model "website" "tag") tag) 'conflict)))
      (testing "a boolean missing in a row and one that is false are the same"
        (ok (eq :unchanged (nth-value 1 (update-draft "website" page (content-id content)
                                                      (list :title "P" :cards (vector (list :field-id "card" :link tag
                                                                                            :at "2026-09-20T01:00:00.000Z"
                                                                                            :shown nil :pinned t)))
                                                      :replace t)))))
      (flet ((rows (&rest more)
               (vector (list* :field-id "card" :link tag :at "2026-09-20T01:00:00.000Z" :pinned t more))))
        (testing "a null in a row, for a field that has no value, changes nothing"
          (ok (eq :unchanged (nth-value 1 (update-draft "website" page (content-id content) (list :cards (rows :note :null)))))))
        (testing "a key a row's custom field does not have is refused, null or not"
          (ok (signals (update-draft "website" page (content-id content) (list :cards (rows :bogus :null)))
                       'validation-error)))))))
