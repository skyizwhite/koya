(defpackage #:koya-spec/core/json
  (:use #:cl #:rove)
  (:import-from #:koya-core/json #:parse-json #:json-parse-error))
(in-package #:koya-spec/core/json)

(deftest text-that-is-not-json
  (ok (signals (parse-json "{x") 'json-parse-error) "is a json-parse-error, whatever parses it"))
