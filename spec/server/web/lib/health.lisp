(defpackage #:koya-spec/server/web/lib/health
  (:use #:cl #:rove)
  (:import-from #:koya-spec/server/web/pages/support #:*cookie* #:request #:setup-pages)
  (:import-from #:koya-server/infra/db/connection #:exec #:disconnect-db)
  (:import-from #:koya-core/json #:parse-json #:jget))
(in-package #:koya-spec/server/web/lib/health)

(setup (setup-pages))

(teardown (disconnect-db))

(deftest health-reads-the-database
  (let ((*cookie* nil))
    (testing "a database that answers is ok, as JSON like the APIs, with nothing of a page around it"
      (let (status body headers log)
        (setf log (with-output-to-string (*standard-output*)
                    (multiple-value-setq (status body headers) (request :get "/health"))))
        (ok (= status 200))
        (ok (search "application/json" (getf headers :content-type)))
        (ok (string= (jget (parse-json body) "status") "ok"))
        (ng (getf headers :set-cookie) "it starts no session")
        (ok (string= log "") "and is left out of the access log, which it would fill")))
    (testing "a database whose tables cannot be read is not"
      (exec "ALTER TABLE spaces RENAME TO spaces_away")
      (unwind-protect
           (multiple-value-bind (status body headers) (request :get "/health")
             (ok (= status 503))
             (ok (search "application/json" (getf headers :content-type)))
             (ok (string= (jget (parse-json body) "error" "code") "unavailable") "an error as every error is"))
        (exec "ALTER TABLE spaces_away RENAME TO spaces")))))
