(uiop:define-package #:koya-server/infra/db
  (:nicknames #:koya-server/infra/db/main)
  (:use #:cl)
  (:import-from #:koya-server/infra/db/connection #:connect-db #:disconnect-db)
  (:import-from #:koya-server/infra/db/migrations #:migrate)
  (:import-from #:koya-server/infra/db/schema-dump #:write-snapshot)
  (:import-from #:koya-server/infra/db/contents)
  (:import-from #:koya-server/infra/db/content-revisions)
  (:import-from #:koya-server/infra/db/schema-store)
  (:import-from #:koya-server/infra/db/schema-deploys)
  (:import-from #:koya-server/infra/db/delivery-keys)
  (:import-from #:koya-server/infra/db/management-keys)
  (:import-from #:koya-server/infra/db/media)
  (:import-from #:koya-server/infra/db/webhook-deliveries)
  (:import-from #:koya-server/infra/db/settings)
  (:import-from #:koya-server/infra/db/sessions #:purge-expired-sessions)
  (:export #:open-store
           #:close-store
           #:write-snapshot))
(in-package #:koya-server/infra/db)

(defun open-store (path)
  (connect-db path)
  (let ((applied (migrate)))
    (when applied (format t "~&[koya] applied migrations ~{~a~^, ~}~%" applied)))
  (purge-expired-sessions))

(defun close-store ()
  (disconnect-db))
