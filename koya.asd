
(defsystem "koya"
  :version "0.12.0"
  :description "koya - a small headless CMS in Common Lisp (client library and config DSL)"
  :author "Akira Tempaku <paku@skyizwhite.dev>"
  :license "MIT"
  :homepage "https://github.com/skyizwhite/koya"
  :source-control (:git "https://github.com/skyizwhite/koya.git")
  :class :package-inferred-system
  :pathname "src/sdk"
  :depends-on ("koya/main")
  :in-order-to ((test-op (test-op "koya-tests"))))
