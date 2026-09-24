(defpackage #:koya-tests/server/web/pages/deploys
  (:use #:cl #:rove)
  (:import-from #:koya-tests/server/web/pages/support #:post-login #:*secret* #:*cookie* #:request #:call-action #:setup-pages #:log-in)
  (:import-from #:koya-server/web/pages/s/<space>/deploys #:browse-deploys)
  (:import-from #:koya-server/infra/db/connection #:disconnect-db)
  (:import-from #:koya-server/usecases/ports/spaces #:save-schema #:delete-space #:list-deploys)
  (:import-from #:koya-server/usecases/spaces/lifecycle #:create-space)
  (:import-from #:koya-server/usecases/ports/keys #:create-management-key)
  (:import-from #:koya/core/schema #:make-field #:make-model #:make-schema)
  (:import-from #:koya/core/json #:to-json)
  (:import-from #:koya/core/schema #:schema->jobject)
  (:import-from #:koya-server/domain/deploy #:deploy-by))
(in-package #:koya-tests/server/web/pages/deploys)

(setup (setup-pages) (log-in))

(teardown (disconnect-db))

(deftest deploys-page
  (setf *cookie* nil)
  (post-login :form `(("secret" . ,*secret*)))
  (create-space "deployed")
  (save-schema "deployed"
               (make-schema :models (list (make-model "post" :list (list (make-field :title :text)))))
               :by "key:ci")
  (save-schema "deployed"
               (make-schema :models (list (make-model "post" :list (list (make-field :title :text :required t))))))
  (unwind-protect
       (progn
         (multiple-value-bind (status body) (request :get "/s/deployed/deploys")
           (ok (= status 200))
           (ok (search "Schema Deploys" body))
           (ok (search "2 deploys, the newest 100 kept." body))
           (testing "each change is the line plan prints, coloured by what it does"
             (ok (search "<div class=\"text-ok\">+ post.title (text)" body) "something new is green")
             (ok (search "<div class=\"text-ok\">+ post (list)" body))
             (ok (search "<div class=\"text-danger\">! ~ post.title options tightened (required none -&gt; true)" body)
                 "and a change that can reject stored content is red, and says which option moved"))
           (testing "and each deploy says how much it changed, by whom, and whether it was destructive"
             (ok (search "2 changes" body))
             (ok (search "1 change<" body))
             (ok (search "(management key: ci)" body) "a stored key:ci is read out in words")
             (ok (search "destructive" body))))
         (testing "a deploy with no key behind it was the owner's"
           (save-schema "deployed"
                        (make-schema :models (list (make-model "post" :list (list (make-field :title :text :required t)
                                                                                  (make-field :body :richtext)))))
                        :by "owner")
           (multiple-value-bind (status body) (request :get "/s/deployed/deploys")
             (ok (= status 200))
             (ok (search "· owner" body) "and is named as such, with nothing around it")
             (ok (search "text-danger\">destructive</span></span>" body)
                 "while a deploy that named nobody ends after the badge, with no separator left hanging")))
         (multiple-value-bind (status body) (request :get "/s/deployed")
           (ok (= status 200))
           (ok (search "/s/deployed/deploys" body) "the space page links to it")
           (ok (search "Schema Deploys" body)))
         (multiple-value-bind (status) (request :get "/s/nope/deploys")
           (ok (= status 404))))
    (delete-space "deployed"))
  (testing "a space that has never been deployed to says so"
    (create-space "quiet")
    (unwind-protect
         (multiple-value-bind (status body) (request :get "/s/quiet/deploys")
           (ok (= status 200))
           (ok (search "Nothing has been deployed yet." body)))
      (delete-space "quiet"))))

(deftest a-deploy-names-whoever-was-authorised
  ;; the auth middleware takes the owner's session first and only then a
  ;; management key, so a request carrying both is the owner's; the log has to
  ;; say what the decision said
  (setf *cookie* nil)
  (post-login :form `(("secret" . ,*secret*)))
  (create-space "witnessed")
  (let ((key (create-management-key "witnessed" :label "ci")))
    (unwind-protect
         (let ((body (to-json (schema->jobject
                               (make-schema :models (list (make-model "post" :list
                                                                     (list (make-field :title :text)))))))))
           (multiple-value-bind (status)
               (request :put "/admin/api/schema/witnessed" :json body
                        :headers `(("origin" . "http://localhost:3000")
                                   ("authorization" . ,(format nil "Bearer ~a" key))))
             (ok (= status 200)))
           (ok (string= (deploy-by (first (list-deploys "witnessed"))) "owner")
               "a session and a key together is the owner deploying, not the key"))
      (delete-space "witnessed")))
  (testing "and a key on its own is named by its label"
    (create-space "by-key")
    (let ((key (create-management-key "by-key" :label "ci")))
      (unwind-protect
           (let ((body (to-json (schema->jobject
                                 (make-schema :models (list (make-model "post" :list
                                                                       (list (make-field :title :text)))))))))
             (setf *cookie* nil)
             (multiple-value-bind (status)
                 (request :put "/admin/api/schema/by-key" :json body
                          :headers `(("origin" . "http://localhost:3000")
                                     ("authorization" . ,(format nil "Bearer ~a" key))))
               (ok (= status 200)))
             (ok (string= (deploy-by (first (list-deploys "by-key"))) "key:ci")))
        (delete-space "by-key")))))


(deftest deploys-are-paged-in-place
  (log-in)
  (multiple-value-bind (status body headers) (call-action :get (browse-deploys :space "website" :page 1))
    (ok (= status 200))
    (ok (search "id=\"deploys\"" body))
    (ng (search "<html" body))
    (ok (string= (getf headers :hx-replace-url) "/s/website/deploys")))
  (ok (string= (getf (nth-value 2 (call-action :get (browse-deploys :space "website" :page 9))) :hx-replace-url)
               "/s/website/deploys")
      "a page past the end is the last one")
  (ok (= 404 (call-action :get (browse-deploys :space "nope")))))
