
(defsystem "koya-sdk"
  :version "0.12.1"
  :description "koya - a small headless CMS in Common Lisp (SDK: the schema DSL and the HTTP client)"
  :author "Akira Tempaku <paku@skyizwhite.dev>"
  :license "MIT"
  :homepage "https://github.com/skyizwhite/koya"
  :source-control (:git "https://github.com/skyizwhite/koya.git")
  :class :package-inferred-system
  :pathname "src/sdk"
  :depends-on ("koya-sdk/main")
  :in-order-to ((test-op (test-op "koya-tests"))))
