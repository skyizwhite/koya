(defpackage #:koya-tests/server/web/http
  (:use #:cl #:rove)
  (:import-from #:koya-server/usecases/schema/deploy #:replace-schema)
  (:import-from #:koya-tests/server/web/api-support #:*secret* #:*management-key* #:*api-key* #:request #:admin #:delivery #:setup-api #:reset-api)
  (:import-from #:koya-server/web/app #:app)
  (:import-from #:koya-server/infra/db/connection #:disconnect-db)
  (:import-from #:koya-core/schema #:make-field #:make-model #:make-schema #:make-webhook)
  (:import-from #:koya-server/web/http #:origin-allowed-p)
  (:import-from #:koya-core/json #:jobject #:jget)
  (:import-from #:alexandria #:alist-hash-table))
(in-package #:koya-tests/server/web/http)

(setup (setup-api))

(teardown (disconnect-db))

(defhook :before (reset-api))

(deftest origin-check
  (flet ((allowed (origin referer host) (origin-allowed-p origin referer host "https://cms.example.com")))
    (ok (allowed nil nil "cms.example.com") "no Origin or Referer: non-browser client")
    (ok (allowed "https://cms.example.com" nil "cms.example.com"))
    (ok (allowed "https://cms.example.com:443" nil "cms.example.com") "default port is dropped")
    (ok (allowed "https://cms.example.com" nil "cms.example.com:443"))
    (ok (allowed "http://localhost:3000" nil "localhost:3000"))
    (ok (allowed "https://cms.example.com" nil "10.0.0.5:3000") "KOYA_BASE_URL behind a proxy")
    (ok (allowed nil "https://cms.example.com/s/website/keys" "cms.example.com") "Referer fallback")
    (ng (allowed "https://evil.example" nil "cms.example.com"))
    (ng (allowed "http://cms.example.com:3000" nil "cms.example.com") "other port is another origin")
    (ng (allowed "null" nil "cms.example.com") "Origin: null is rejected")
    (ng (allowed "garbage" nil "cms.example.com"))
    (ng (allowed "https://evil.example" "https://cms.example.com/" "cms.example.com") "Origin wins over Referer")))

(deftest admin-auth
  (multiple-value-bind (status json) (request :get "/admin/api/me")
    (ok (= status 401))
    (ok (string= (jget json "error" "code") "unauthorized")))
  (multiple-value-bind (status) (request :get "/admin/api/me" :headers '(("authorization" . "Bearer wrong")))
    (ok (= status 401)))
  (multiple-value-bind (status) (request :get "/admin/api/me" :headers `(("authorization" . ,(format nil "Bearer ~a" *secret*))))
    (ok (= status 401) "the owner secret logs into the UI; it is not a management key"))
  (multiple-value-bind (status) (request :get "/admin/api/me" :headers '(("authorization" . "Bearer 鍵")))
    (ok (= status 401) "a token that is not even ASCII is just wrong, not an error"))
  (multiple-value-bind (status) (request :get "/api/v1/website/blog" :headers '(("x-koya-delivery-key" . "鍵")))
    (ok (= status 401)))
  (multiple-value-bind (status json) (admin :get "/admin/api/me")
    (ok (= status 200))
    (ok (eq (jget json "management") t) "a Bearer caller is a management key")
    (ok (string= (jget json "space") "website") "and says which space it may reach")
    (ok (null (jget json "owner"))))
  (testing "writes need a matching origin when a browser sends one"
    (multiple-value-bind (status json)
        (request :post "/admin/api/schema/website/plan" :body (jobject "koyaSchema" 1)
                 :headers `(("authorization" . ,(format nil "Bearer ~a" *management-key*)) ("origin" . "https://evil.example")))
      (ok (= status 403))
      (ok (string= (jget json "error" "code") "forbidden")))
    (multiple-value-bind (status)
        (request :post "/admin/api/schema/website/plan" :body (jobject "koyaSchema" 1 "models" #())
                 :headers `(("authorization" . ,(format nil "Bearer ~a" *management-key*)) ("origin" . "http://localhost:3000")
                            ("host" . "localhost:3000")))
      (ok (= status 200)))
    (multiple-value-bind (status)
        (request :get "/admin/api/me"
                 :headers `(("authorization" . ,(format nil "Bearer ~a" *management-key*)) ("origin" . "https://evil.example")))
      (ok (= status 200) "reads are not gated"))))

(deftest api-cache-control
  (multiple-value-bind (status json raw) (delivery "/api/v1/website/blog")
    (declare (ignore json raw))
    (ok (= status 200)))
  (let ((env (list :request-method :get :script-name "" :path-info "/api/v1/website/blog" :query-string ""
                   :server-name "localhost" :server-port 3000 :server-protocol :http/1.1
                   :request-uri "/api/v1/website/blog" :url-scheme "http" :remote-addr "127.0.0.1"
                   :headers (alist-hash-table `(("x-koya-delivery-key" . ,*api-key*)) :test 'equal)
                   :content-type nil :content-length nil :raw-body nil)))
    (destructuring-bind (status headers body) (funcall (app) env)
      (declare (ignore body))
      (ok (= status 200))
      (ok (string= (getf headers :cache-control) "no-store") "delivery responses are not cached by intermediaries"))))

(deftest delivery-auth
  (multiple-value-bind (status json) (delivery "/api/v1/website/blog" :key nil)
    (ok (= status 401))
    (ok (string= (jget json "error" "code") "unauthorized")))
  (multiple-value-bind (status) (delivery "/api/v1/website/blog" :key "koya_wrong")
    (ok (= status 401)))
  (replace-schema "website"
               (make-schema :webhooks (list (make-webhook "hook" "https://example.com/hook"))
                            :models (list (make-model "blog" :list (list (make-field :title :text :required t :unique t)
                                                                         (make-field :body :richtext)
                                                                         (make-field :featured :boolean :default t)
                                                                         (make-field :tags :reference :model "tag" :many t)))
                                          (make-model "tag" :list (list (make-field :name :text :required t)))
                                          (make-model "about" :object (list (make-field :body :richtext))))))
  (multiple-value-bind (status json) (delivery "/api/v1/other/blog")
    (ok (= status 403))
    (ok (string= (jget json "error" "code") "forbidden")))
  (multiple-value-bind (status json) (delivery "/api/v1/website/nope")
    (ok (= status 404))
    (ok (string= (jget json "error" "code") "not_found")))
  (multiple-value-bind (status json) (request :get "/api/nothing/here")
    (ok (= status 404))
    (ok (string= (jget json "error" "code") "not_found"))))


(defun raw-request (method path headers)
  "The whole Lack response, headers included, which REQUEST does not return."
  (funcall (app) (list :request-method method :script-name "" :path-info path :query-string ""
                       :server-name "localhost" :server-port 3000 :server-protocol :http/1.1
                       :request-uri path :url-scheme "http" :remote-addr "127.0.0.1"
                       :headers (alist-hash-table headers :test 'equal)
                       :content-type nil :content-length nil :raw-body nil)))

(deftest delivery-cors
  (testing "the preflight is answered without a key"
    (destructuring-bind (status headers body)
        (raw-request :options "/api/v1/website/blog"
                     '(("origin" . "https://example.com")
                       ("access-control-request-method" . "GET")
                       ("access-control-request-headers" . "x-koya-delivery-key")))
      (declare (ignore body))
      (ok (= status 204))
      (ok (string= (getf headers :access-control-allow-origin) "*"))
      (ok (string= (getf headers :access-control-allow-methods) "GET"))
      (ok (string-equal (getf headers :access-control-allow-headers) "X-KOYA-DELIVERY-KEY"))
      (ok (getf headers :access-control-max-age))))
  (testing "every answer can be read by a page on another origin"
    (destructuring-bind (status headers body)
        (raw-request :get "/api/v1/website/blog" `(("origin" . "https://example.com") ("x-koya-delivery-key" . ,*api-key*)))
      (declare (ignore body))
      (ok (= status 200))
      (ok (string= (getf headers :access-control-allow-origin) "*"))
      (ok (string= (getf headers :cache-control) "no-store")))
    (destructuring-bind (status headers body) (raw-request :get "/api/v1/website/blog" '(("origin" . "https://example.com")))
      (declare (ignore body))
      (ok (= status 401))
      (ok (string= (getf headers :access-control-allow-origin) "*") "errors too, so the page sees why")))
  (testing "the admin API stays same-origin"
    (destructuring-bind (status headers body)
        (raw-request :options "/admin/api/me" '(("origin" . "https://example.com") ("access-control-request-method" . "GET")))
      (declare (ignore status body))
      (ng (getf headers :access-control-allow-origin)))
    (destructuring-bind (status headers body)
        (raw-request :get "/admin/api/me" `(("origin" . "https://example.com")
                                            ("authorization" . ,(format nil "Bearer ~a" *management-key*))))
      (declare (ignore body))
      (ok (= status 200))
      (ng (getf headers :access-control-allow-origin)))))
