(defsystem "koya-core"
  :version "0.21.0"
  :description "koya - a small headless CMS in Common Lisp (core: the schema, its validation and diff, content data, JSON and name conversion, time and ULIDs)"
  :author "Akira Tempaku <paku@skyizwhite.dev>"
  :license "MIT"
  :homepage "https://github.com/skyizwhite/koya"
  :source-control (:git "https://github.com/skyizwhite/koya.git")
  :class :package-inferred-system
  :pathname "src/core"
  :depends-on ("koya-core/main")
  :in-order-to ((test-op (test-op "koya-spec"))))
