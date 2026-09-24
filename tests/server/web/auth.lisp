(defpackage #:koya-tests/server/web/auth
  (:use #:cl #:rove)
  (:import-from #:koya-tests/server/web/pages/support #:*cookie* #:request #:location #:setup-pages #:log-in)
  (:import-from #:koya-server/web/app #:*page-app*)
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
