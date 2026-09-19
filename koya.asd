(register-system-packages "3bmd-ext-code-blocks" '(:3bmd-code-blocks))
(register-system-packages "3bmd-ext-tables" '(:3bmd-tables))

(defsystem "koya"
  :version "0.1.0"
  :description "koya - a small headless CMS in Common Lisp (client library and config DSL)"
  :author "Akira Tempaku <paku@skyizwhite.dev>"
  :license "MIT"
  :class :package-inferred-system
  :pathname "src"
  :depends-on ("koya/main")
  :in-order-to ((test-op (test-op "koya-tests"))))
