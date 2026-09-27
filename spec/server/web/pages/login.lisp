(defpackage #:koya-spec/server/web/pages/login
  (:use #:cl #:rove)
  (:import-from #:koya-spec/server/web/pages/support
                #:post-login #:moved-to #:*secret* #:*cookie* #:*set-cookie* #:request
                #:request-url #:location #:call-action #:setup-pages #:log-in)
  (:import-from #:koya-server/web/ui/layout #:logout)
  (:import-from #:koya-server/web/pages/s/<space>/keys #:create-key)
  (:import-from #:koya-server/infra/db/connection #:disconnect-db #:fetch-one #:col)
  (:import-from #:koya-server/usecases/keys #:list-delivery-keys)
  (:import-from #:koya-server/usecases/settings #:enable-totp #:disable-totp)
  (:import-from #:koya-server/domain/totp #:totp)
  (:import-from #:koya-server/web/pages/settings #:begin-two-factor-action))
(in-package #:koya-spec/server/web/pages/login)

(setup (setup-pages) (log-in))

(teardown (disconnect-db))

(deftest health
  (let ((*cookie* nil))
    (multiple-value-bind (status body) (request :get "/health")
      (ok (= status 200))
      (ok (search "ok" body)))))

(deftest login-flow
  (setf *cookie* nil)
  (multiple-value-bind (status body headers) (request :get "/")
    (declare (ignore body))
    (ok (= status 302))
    (ok (string= (location headers) "/login")))
  (multiple-value-bind (status body) (request :get "/login")
    (ok (= status 200))
    (ok (search "Owner secret" body)))
  (multiple-value-bind (status body) (post-login :form '(("secret" . "nope")))
    (ok (= status 401))
    (ok (search "Wrong secret" body)))
  (multiple-value-bind (status body headers) (post-login :form `(("secret" . ,*secret*)))
    (declare (ignore body))
    (ok (= status 200))
    (ok (string= (moved-to headers) "/"))
    (ok *cookie* "session cookie set")
    (ok (search "HttpOnly" *set-cookie*) "cookie is HttpOnly")
    (ok (search "SameSite=Lax" *set-cookie*) "cookie is SameSite=Lax")
    (ok (col (fetch-one "SELECT count(*) AS n FROM sessions") "n")
        "the session is in the database, not only in the process"))
  (multiple-value-bind (status body) (request :get "/")
    (ok (= status 200))
    (ok (search "website" body) "space listed"))
  (testing "two-factor login once a secret is stored"
    (let ((secret "GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ"))
      (enable-totp secret)
      (unwind-protect
           (let ((*cookie* nil))
             (multiple-value-bind (status body) (request :get "/login")
               (ok (= status 200))
               (ok (search "One-time code" body) "the form asks for a code"))
             (multiple-value-bind (status body) (post-login :form `(("secret" . ,*secret*)))
               (ok (= status 401))
               (ok (search "one-time code" body) "secret alone is not enough"))
             (multiple-value-bind (status body) (post-login :form `(("secret" . "nope") ("code" . ,(totp secret))))
               (ok (= status 401))
               (ok (search "Wrong secret" body) "a wrong secret is reported as such, and does not consume the code"))
             (let ((code (totp secret)))
               (multiple-value-bind (status body headers) (post-login :form `(("secret" . ,*secret*) ("code" . ,code)))
                 (declare (ignore body))
                 (ok (= status 200))
                 (ok (string= (moved-to headers) "/")))
               (let ((*cookie* nil))
                 (multiple-value-bind (status body) (post-login :form `(("secret" . ,*secret*) ("code" . ,code)))
                   (ok (= status 401))
                   (ok (search "one-time code" body) "the same code cannot log in twice")))))
        (disable-totp))))
  (testing "cross-origin actions are rejected"
    (ok (= 403 (call-action :post (logout) :headers '(("origin" . "https://evil.example")))))
    (ok (= 403 (call-action :post (create-key :space "website" :kind "delivery")
                            :headers '(("origin" . "https://evil.example")))))
    (ok (= 403 (call-action :post (logout) :headers '(("origin" . "null"))))
        "an opaque origin is not 'no origin'")
    (ok (null (list-delivery-keys "website"))))
  (testing "logging out is an action that sends the browser to the login page"
    (multiple-value-bind (status body headers) (call-action :post (logout))
      (declare (ignore body))
      (ok (= status 200))
      (ok (equal (getf headers :hx-redirect) "/login")))
    (ok (= 302 (request :get "/")) "and the session is gone")
    (log-in)))

(deftest a-login-does-not-keep-the-session-id-it-was-sent
  (let* ((planted (format nil "lack.session=~a" (make-string 40 :initial-element #\a)))
         (*cookie* planted))
    (post-login :form `(("secret" . ,*secret*)))
    (ok (string/= *cookie* planted) "the cookie after login is not the one sent")
    (let ((*cookie* planted))
      (ok (= 302 (request :get "/settings")) "and the planted id is not an owner session"))
    (let ((owner *cookie*))
      (call-action :post (logout))
      (ok (string/= *cookie* owner) "logging out changes the id again")
      (let ((*cookie* owner))
        (ok (= 302 (request :get "/")) "and the owner's id is no longer a session"))))
  (log-in))

(deftest login-returns-to-the-page
  (let ((*cookie* nil))
    (multiple-value-bind (status body headers) (request :get "/s/website/media" :query "page=2")
      (declare (ignore body))
      (ok (= status 302))
      (ok (string= (location headers) "/login?next=%2Fs%2Fwebsite%2Fmedia%3Fpage%3D2")))
    (multiple-value-bind (status body) (request :get "/login" :query "next=%2Fs%2Fwebsite%2Fmedia%3Fpage%3D2")
      (ok (= status 200))
      (ok (search "name=\"next\" value=\"/s/website/media?page=2\"" body) "the form carries it"))
    (multiple-value-bind (status body headers)
        (post-login :form `(("secret" . ,*secret*) ("next" . "/s/website/media?page=2")))
      (declare (ignore body))
      (ok (= status 200))
      (ok (string= (moved-to headers) "/s/website/media?page=2"))))
  (testing "an action without a session returns to the page it was sent from"
    (let ((*cookie* nil))
      (multiple-value-bind (status body headers)
          (call-action :post (create-key :space "website" :kind "delivery")
                       :headers '(("hx-current-url" . "http://localhost:3000/s/website/keys")))
        (declare (ignore body))
        (ok (= status 401))
        (ok (string= (getf headers :hx-redirect) "/login?next=%2Fs%2Fwebsite%2Fkeys")))))
  (testing "next never leaves the server"
    (dolist (next '("//evil.test/" "/\\evil.test/" "https://evil.test/" "evil"))
      (let ((*cookie* nil))
        (multiple-value-bind (status body headers)
            (post-login :form `(("secret" . ,*secret*) ("next" . ,next)))
          (declare (ignore body))
          (ok (= status 200))
          (ok (string= (moved-to headers) "/") next))))))

(deftest login-is-the-one-open-action
  (let ((*cookie* nil))
    (testing "it needs no session, but still htmx and this origin"
      (ok (= 403 (post-login :form `(("secret" . ,*secret*)) :headers '(("origin" . "https://evil.example"))))
          "another site cannot log a browser in")
      (ok (null *cookie*) "and no session was made")
      ;; named in full: LOG-IN here is the tests' own
      (ok (= 400 (request-url :post (koya-server/web/pages/login:log-in) :form `(("secret" . ,*secret*))
                              :headers '(("origin" . "http://localhost:3000"))))
          "a plain form post is not an action")
      (ok (= 404 (request :post "/login" :form `(("secret" . ,*secret*)) :headers '(("origin" . "http://localhost:3000"))))
          "the page itself takes no posts"))
    (testing "no other action is open"
      (ok (= 401 (call-action :post (begin-two-factor-action)))))))

(deftest wrong-secrets-never-lock-the-owner-out
  (let ((*cookie* nil))
    (dotimes (i 20)
      (ok (= 401 (post-login :form '(("secret" . "nope"))))))
    (ok (= 200 (post-login :form `(("secret" . ,*secret*)))) "the right secret still logs in")))

(deftest a-missing-secret-is-a-short-one
  (let ((*cookie* nil))
    (setf (uiop:getenv "KOYA_SECRET") "")
    (unwind-protect
         (progn
           (multiple-value-bind (status body) (request :get "/login")
             (ok (= status 200))
             (ok (search "KOYA_SECRET is shorter than 32 characters" body)))
           (ok (= 403 (post-login :form '(("secret" . ""))))))
      (setf (uiop:getenv "KOYA_SECRET") *secret*))))

(deftest a-short-secret-turns-logging-in-off
  (let ((*cookie* nil)
        (short (make-string 31 :initial-element #\s)))
    (setf (uiop:getenv "KOYA_SECRET") short)
    (unwind-protect
         (progn
           (multiple-value-bind (status body) (request :get "/login")
             (ok (= status 200))
             (ok (search "KOYA_SECRET is shorter than 32 characters" body) "the page says why")
             (ng (search "name=\"secret\"" body) "and asks for no secret"))
           (multiple-value-bind (status body) (post-login :form `(("secret" . ,short)))
             (ok (= status 403) "even the short secret itself does not log in")
             (ok (search "KOYA_SECRET is shorter than 32 characters" body)))
           (ok (null *cookie*) "and no session was made"))
      (setf (uiop:getenv "KOYA_SECRET") *secret*))
    (ok (= 200 (post-login :form `(("secret" . ,*secret*)))) "a long secret and a restart are all it takes")))


(deftest a-failed-login-does-not-say-which-factor-was-wrong
  (let ((secret "GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ")
        (*cookie* nil))
    (enable-totp secret)
    (unwind-protect
         (multiple-value-bind (secret-status secret-body)
             (post-login :form `(("secret" . "nope") ("code" . ,(totp secret))))
           (multiple-value-bind (code-status code-body)
               (post-login :form `(("secret" . ,*secret*) ("code" . ,(if (string= (totp secret) "000000") "111111" "000000"))))
             (ok (= secret-status code-status 401))
             (ok (string= secret-body code-body) "a wrong secret and a wrong code read the same")))
      (disable-totp))))
