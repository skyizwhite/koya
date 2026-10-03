(defpackage #:koya-spec/server/web/pages/deploys
  (:use #:cl #:rove)
  (:import-from #:koya-server/usecases/ports/deploys #:list-deploys #:count-deploys)
  (:import-from #:koya-server/usecases/schema #:replace-schema)
  (:import-from #:koya-spec/server/web/pages/support
                #:replaced-url #:post-login #:*secret* #:*cookie* #:request #:call-action #:setup-pages #:log-in)
  (:import-from #:koya-server/web/pages/s/<space>/deploys #:browse-deploys)
  (:import-from #:koya-server/infra/db/connection #:disconnect-db)
  (:import-from #:koya-server/usecases/ports/spaces #:delete-space)
  (:import-from #:koya-server/usecases/spaces #:create-space)
  (:import-from #:koya-server/usecases/keys #:create-management-key)
  (:import-from #:koya-core/schema #:make-field #:make-model #:make-schema)
  (:import-from #:koya-core/json #:to-json)
  (:import-from #:koya-core/schema #:schema->jobject)
  (:import-from #:koya-server/domain/deploy #:deploy-by))
(in-package #:koya-spec/server/web/pages/deploys)

(setup (setup-pages) (log-in))

(teardown (disconnect-db))

(deftest deploys-page
  (setf *cookie* nil)
  (post-login :form `(("secret" . ,*secret*)))
  (create-space "deployed")
  (replace-schema "deployed"
               (make-schema :models (list (make-model "post" :list (list (make-field :title :text)
                                                                         (make-field :lede :text)))))
               :by "key:ci")
  (replace-schema "deployed"
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
             (ok (search "<div class=\"text-danger\">! - post.lede (text)" body)
                 "a change that takes stored content away is red")
             (ok (search "<div class=\"text-muted\">~ post.title options tightened (required none -&gt; true)" body)
                 "and a tightened option, which the server checks against what is stored, says which option moved"))
           (testing "and each deploy says how much it changed, by whom, and whether it was destructive"
             (ok (search "3 changes" body))
             (ok (search "2 changes" body))
             (ok (search "(management key: ci)" body) "a stored key:ci is read out in words")
             (ok (search "destructive" body))))
         (testing "a deploy with no key behind it was the owner's"
           (replace-schema "deployed"
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
           (ok (string= (deploy-by (first (list-deploys "witnessed"))) "key:ci")
               "a session and a key together is the key deploying: the admin API knows no session"))
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
  (multiple-value-bind (status body) (call-action :get (browse-deploys :space "website" :page 1))
    (ok (= status 200))
    (ok (search "id=\"deploys\"" body))
    (ng (search "<html" body))
    (ok (string= (replaced-url body) "/s/website/deploys")))
  (ok (string= (replaced-url (nth-value 1 (call-action :get (browse-deploys :space "website" :page 9))))
               "/s/website/deploys")
      "a page past the end is the last one")
  (ok (= 404 (call-action :get (browse-deploys :space "nope")))))
