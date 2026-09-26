
(defsystem "koya-core"
  :version "0.12.1"
  :description "koya - a small headless CMS in Common Lisp (core: the schema, JSON, time and ids both the SDK and the server use)"
  :author "Akira Tempaku <paku@skyizwhite.dev>"
  :license "MIT"
  :homepage "https://github.com/skyizwhite/koya"
  :source-control (:git "https://github.com/skyizwhite/koya.git")
  :class :package-inferred-system
  :pathname "src/core"
  :depends-on ("koya-core/main")
  :in-order-to ((test-op (test-op "koya-tests"))))
