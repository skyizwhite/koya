(defpackage #:koya-tests/server/web/pages/webhooks
  (:use #:cl #:rove)
  (:import-from #:koya-server/usecases/schema/deploy #:replace-schema)
  (:import-from #:koya-tests/server/web/pages/support #:blog-model #:request #:call-action #:setup-pages #:log-in)
  (:import-from #:koya-server/web/pages/s/<space>/webhooks #:browse-deliveries)
  (:import-from #:koya-server/infra/db/connection #:disconnect-db #:exec)
  (:import-from #:koya-server/usecases/ports/webhooks #:record-delivery)
  (:import-from #:koya-server/domain/content #:content-id)
  (:import-from #:koya/core/schema #:make-webhook)
  (:import-from #:koya/core/schema #:make-field #:make-model #:make-schema))
(in-package #:koya-tests/server/web/pages/webhooks)

(setup (setup-pages) (log-in))

(teardown (disconnect-db))

(deftest webhook-log-page
  (let ((hooked (make-schema :webhooks (list (make-webhook "revalidate" "https://site.test/api/revalidate")
                                             (make-webhook "blog-build" "https://site.test/api/build" :only '(blog)))
                             :models (list (blog-model)
                                           (make-model "about" :object (list (make-field :body :richtext)))))))
    (unwind-protect
         (progn
           (replace-schema "website" hooked)
           (exec "DELETE FROM webhook_deliveries")
           (record-delivery "website" :label "revalidate" :url "https://site.test/api/revalidate"
                                      :model "blog" :event "publish" :content-id "01ARZ3NDEKTSV4RRFFQ69G5FAV"
                                      :ok t :status 200 :response "{\"revalidated\":[\"/blog\"]}"
                                      :error "" :duration-ms 42)
           (record-delivery "website" :label "revalidate" :url "https://site.test/api/revalidate"
                                      :model "blog" :event "draft" :content-id "01ARZ3NDEKTSV4RRFFQ69G5FAW"
                                      :ok nil :status nil :response ""
                                      :error "connection refused" :duration-ms 5001)
           (testing "the space page sends each webhook to its own log"
             (multiple-value-bind (status body) (request :get "/s/website")
               (ok (= status 200))
               (ok (search "/s/website/webhooks?label=revalidate" body) "the row is a link to that hook's log")
               (ok (search "\"/s/website/webhooks\"" body) "and View log links to the unfiltered log")
               (ok (search "View log" body))
               (ok (search "all models" body) "a webhook without :only says so")
               (ok (search "blog only" body) "and one with :only names the models it covers")))
           (testing "an object model the webhooks leave out offers no log"
             (multiple-value-bind (status body)
                 (let ((narrow (make-schema :webhooks (list (make-webhook "blog-build" "https://site.test/api/build"
                                                                          :only '(blog)))
                                            :models (list (blog-model)
                                                          (make-model "about" :object (list (make-field :body :richtext)))))))
               (replace-schema "website" narrow)
               (unwind-protect (request :get "/s/website/m/about/new")
                 (replace-schema "website" hooked)))
               (ok (= status 200))
               (ng (search "/s/website/webhooks?model=about" body))))
           (testing "a model page links to the log narrowed to that model"
             (multiple-value-bind (status body) (request :get "/s/website/m/blog")
               (ok (= status 200))
               (ok (search "/s/website/webhooks?model=blog" body))))
           (testing "an object model has no list page, so its editor carries the link"
             (multiple-value-bind (status body) (request :get "/s/website/m/about/new")
               (ok (= status 200))
               (ok (search "/s/website/webhooks?model=about" body))))
           (testing "the log shows the outcome and what came back"
             (multiple-value-bind (status body) (request :get "/s/website/webhooks")
               (ok (= status 200))
               (ok (search "200" body) "the status is shown")
               (ok (search "revalidated" body) "so is the response body")
               (ok (search "connection refused" body) "and the error of the call that never arrived")
               (ok (search "42 ms" body))
               (ok (search "no response" body) "a call with no status says so")))
           (testing "the filters can be set from the page itself"
             (multiple-value-bind (status body) (request :get "/s/website/webhooks")
               (ok (= status 200))
               (ok (search "<form id=\"filters\" method=\"get\" action=\"/s/website/webhooks\"" body)
                   "an unfiltered page still offers the form")
               (ok (search "name=\"label\"" body))
               (ok (search "name=\"model\"" body))
               (ok (search "<option value=\"revalidate\"" body) "the schema's webhooks are offered")
               (ok (search "<option value=\"blog\"" body))
               (ok (search "<option value=\"about\"" body)
                   "every model of the space is offered, not only the ones that have fired")
               (ng (search ">Filter<" body) "picking one applies it: there is no button")
               (ng (search "Clear" body) "nothing to clear when nothing is filtered")))
           (testing "either filter narrows it"
             (multiple-value-bind (status body) (request :get "/s/website/webhooks" :query "label=revalidate")
               (ok (= status 200))
               (ok (search "revalidated" body) "the hook's own calls are still there")
               (ok (search "Clear" body)))
             (multiple-value-bind (status body) (request :get "/s/website/webhooks" :query "model=blog")
               (ok (= status 200))
               (ok (search "connection refused" body) "blog's calls are all there"))
             (multiple-value-bind (status body) (request :get "/s/website/webhooks" :query "model=about")
               (ok (= status 200))
               (ok (search "Nothing matches these filters" body)
                   "a model that has never fired is selectable and simply empty"))
             (multiple-value-bind (status body) (request :get "/s/website/webhooks" :query "label=nothing")
               (ok (= status 200))
               (ok (search "Nothing matches these filters" body))
               (ok (search "<option value=\"nothing\" selected" body)
                   "a value neither the schema nor the log knows still shows as the filter, so the other select cannot drop it"))
             (testing "both together, and the selects show what is filtered"
               (multiple-value-bind (status body)
                   (request :get "/s/website/webhooks" :query "label=revalidate&model=blog")
                 (ok (= status 200))
                 (ok (search "<option value=\"revalidate\" selected" body))
                 (ok (search "<option value=\"blog\" selected" body)))))
           (multiple-value-bind (status) (request :get "/s/nope/webhooks")
             (ok (= status 404))))
      (replace-schema "website"
                   (make-schema :models (list (blog-model)
                                              (make-model "about" :object (list (make-field :body :richtext))))))
      (exec "DELETE FROM webhook_deliveries")))
  (testing "with the webhooks gone, nothing offers a log that can only be empty"
    (multiple-value-bind (status body) (request :get "/s/website/m/blog")
      (ok (= status 200))
      (ng (search "/s/website/webhooks" body)))
    (multiple-value-bind (status body) (request :get "/s/website/m/about/new")
      (ok (= status 200))
      (ng (search "/s/website/webhooks" body)))))


(deftest the-log-is-filtered-in-place
  (exec "DELETE FROM webhook_deliveries")
  (dolist (model '("blog" "blog" "about"))
    (record-delivery "website" :label "revalidate" :url "https://site.test/api/revalidate"
                               :model model :event "publish" :content-id "01ARZ3NDEKTSV4RRFFQ69G5FAV"
                               :ok t :status 200 :response "" :error "" :duration-ms 1))
  (testing "the selects call the action as they are picked"
    (let ((body (nth-value 1 (request :get "/s/website/webhooks"))))
      (ok (search "hx-trigger=\"change, submit\"" body) "either select, as its change bubbles")
      (ng (search ">Filter<" body) "so there is no button to press")))
  (testing "a filter draws #deliveries and the count, and puts itself in the URL"
    (multiple-value-bind (status body headers)
        (call-action :get (browse-deliveries :space "website" :label "" :model "about" :page 1))
      (ok (= status 200))
      (ok (search "id=\"deliveries\"" body))
      (ok (search "1 call matches." body) "the count, out of band")
      (ok (search "Clear the filters" body))
      (ng (search "id=\"filters\"" body) "the selects stay as they are")
      (ok (string= (getf headers :hx-replace-url) "/s/website/webhooks?model=about"))))
  (testing "clearing puts the selects back"
    (multiple-value-bind (status body headers) (call-action :get (browse-deliveries :space "website" :clear "1"))
      (ok (= status 200))
      (ok (search "id=\"filters\"" body))
      (ok (search "3 calls." body))
      (ok (string= (getf headers :hx-replace-url) "/s/website/webhooks"))))
  (ok (= 404 (call-action :get (browse-deliveries :space "nope")))))
