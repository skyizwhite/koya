(defpackage #:koya-spec/server/usecases/spaces
  (:use #:cl #:rove)
  (:import-from #:koya-server/infra/db/connection #:connect-db #:disconnect-db)
  (:import-from #:koya-server/infra/db/migrations #:migrate)
  (:import-from #:koya-server/domain/errors #:conflict)
  (:import-from #:koya-server/usecases/spaces #:create-space #:list-spaces)
  (:import-from #:koya-spec/server/threads #:at-once))
(in-package #:koya-spec/server/usecases/spaces)

(setup
  (connect-db ":memory:")
  (migrate))

(teardown
  (disconnect-db))

(deftest a-space-created-twice-at-once-is-made-once
  (let ((outcomes (at-once 8 (lambda () (create-space "shop")))))
    (ok (= (count "shop" outcomes :test #'equal) 1) "one makes it")
    (ok (= (count-if (lambda (o) (typep o 'conflict)) outcomes) 7) "and the others are told it already exists")
    (ok (= (count "shop" (list-spaces) :key (lambda (s) (getf s :name)) :test #'equal) 1))))
