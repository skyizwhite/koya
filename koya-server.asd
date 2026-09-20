(register-system-packages "cl-dbi" '(:dbi))
(register-system-packages "bordeaux-threads" '(:bordeaux-threads-2 :bt2))
(register-system-packages "lack-middleware-session" '(:lack/middleware/session/store))

(defsystem "koya-server"
  :version "0.1.0"
  :description "koya - a small headless CMS in Common Lisp (server)"
  :author "Akira Tempaku <paku@skyizwhite.dev>"
  :license "MIT"
  :homepage "https://github.com/skyizwhite/koya"
  :source-control (:git "https://github.com/skyizwhite/koya.git")
  :class :package-inferred-system
  :pathname "src/server"
  :depends-on ("dbd-sqlite3"
               "clack-handler-woo"
               "clack-handler-hunchentoot"
               "koya-server/main")
  :in-order-to ((test-op (test-op "koya-tests"))))
