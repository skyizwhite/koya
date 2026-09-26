(defpackage #:koya-tests/server/web/auth
  (:use #:cl #:rove)
  (:import-from #:koya-tests/server/web/pages/support
                #:*cookie* #:request #:request-url #:location #:setup-pages #:log-in #:post-login #:*secret*
                #:call-action)
  (:import-from #:koya-server/usecases/spaces/lifecycle #:create-space)
  (:import-from #:koya-server/usecases/keys #:create-management-key)
  (:import-from #:koya-server/web/app #:*page-app* #:*app* #:build-app)
  (:import-from #:koya-server/infra/db/connection #:disconnect-db))
(in-package #:koya-tests/server/web/auth)

;;; The pages guard: a page is the owner's without doing anything for it.

(setup (setup-pages) (log-in))

(teardown (disconnect-db))

(defparameter +probe-path+ "/probe-page-the-guard-covers"
  "A page added by the test and left in place: no page of koya's is at it.")

(deftest a-page-that-does-nothing-is-the-owners
  (setf (ningle:route *page-app* +probe-path+)
        (lambda (params) (declare (ignore params)) "what only the owner sees"))
  (let ((*cookie* nil))
    (multiple-value-bind (status body headers) (request :get +probe-path+ :query "a=1")
      (ok (= status 302) "without a session it is not drawn")
      (ok (string= (location headers) "/login?next=%2Fprobe-page-the-guard-covers%3Fa%3D1")
          "but sent to log in, and back here after")
      (ng (search "what only the owner sees" body))))
  (multiple-value-bind (status body) (request :get +probe-path+)
    (ok (= status 200) "the owner gets it")
    (ok (search "what only the owner sees" body))))

(deftest a-path-that-is-no-page
  (let ((*cookie* nil))
    (multiple-value-bind (status body headers) (request :get "/no-such-page")
      (declare (ignore body))
      (ok (= status 302) "without a session it does not say it is not there")
      (ok (string= (location headers) "/login?next=%2Fno-such-page"))))
  (ok (= 404 (request :get "/no-such-page")) "the owner is told"))

(deftest what-is-open
  (let ((*cookie* nil))
    (ok (= 200 (request :get "/login")))
    (ok (= 200 (request :get "/health")))
    (ok (= 200 (request :get "/assets/icon.svg")) "the login page is drawn with the assets")))

(deftest a-public-action-skips-the-session-only
  ;; the login action is a PUBLIC-PATH: it needs no session, and is guarded like
  ;; every other action for the rest
  (let ((*cookie* nil))
    (ok (/= 401 (post-login :form `(("secret" . ,*secret*)))) "no session needed")
    (let ((*cookie* nil))
      (ok (= 403 (post-login :form `(("secret" . ,*secret*)) :headers '(("origin" . "https://evil.test"))))
          "a page on another site cannot log in with it"))
    (let ((*cookie* nil))
      (ok (= 400 (request-url :post (koya-server/web/pages/login:log-in)
                              :form `(("secret" . ,*secret*))
                              :headers '(("origin" . "http://localhost:3000"))))
          "nor can a plain form post"))))

(deftest a-public-path-is-the-path-asked-for
  (flet ((public-p (request-uri)
           (koya-server/web/auth::public-request-p (list :request-uri request-uri :path-info "/"))))
    (ok (public-p "/login"))
    (ok (public-p "/login?next=%2Fs%2Fwebsite") "whatever its query")
    (ok (public-p "/log%69n") "decoded, as path-info is")
    (ok (public-p "http://localhost:3000/login") "a request line in absolute form")
    (ng (public-p "/login/extra"))
    (ng (public-p "/%zz") "a path that does not decode is not public")))

(deftest the-owner-on-the-admin-api
  (multiple-value-bind (status body)
      (request :post "/admin/api/schema/website/plan" :json "{\"koyaSchema\":1}"
               :headers '(("origin" . "https://evil.test")))
    (ok (= status 403) "the session writes same-origin only")
    (ok (search "Cross-origin" body)))
  (create-space "elsewhere")
  (let ((key (create-management-key "elsewhere" :label "k")))
    (multiple-value-bind (status body)
        (request :get "/admin/api/me" :headers `(("authorization" . ,(format nil "Bearer ~a" key))))
      (ok (= status 200) "a session and a key of another space: the owner's")
      (ok (search "\"owner\":true" body)))))

(deftest what-an-action-refuses
  (ok (= 400 (request-url :get (koya-server/web/pages/login:log-in))) "a plain GET")
  (ok (= 400 (request :get "/actions")) "the prefix itself, not from htmx"))

(deftest logging-out-closes-every-app
  (unwind-protect
       (progn
         (call-action :post (koya-server/web/ui/layout::logout))
         (ok (= 302 (request :get "/s/website")) "the pages")
         (ok (= 401 (request :get "/admin/api/me")) "the admin API")
         (ok (= 401 (call-action :post (koya-server/web/ui/layout::logout))) "the actions"))
    (log-in)))

(deftest the-app-can-be-built-again
  (build-app)
  (let ((*app* (build-app)))
    (ok (= 200 (request :get "/s/website")) "a second build answers as the first")
    (ok (= 200 (request :get "/assets/icon.svg")))))
