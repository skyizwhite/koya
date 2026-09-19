(defsystem "koya-tests"
  :class :package-inferred-system
  :pathname "tests"
  :depends-on ("rove"
               "dbd-sqlite3"
               "koya-tests/core/ulid"
               "koya-tests/core/case"
               "koya-tests/core/schema"
               "koya-tests/core/validate"
               "koya-tests/core/diff"
               "koya-tests/core/markdown"
               "koya-tests/config"
               "koya-tests/server/db"
               "koya-tests/server/contents"
               "koya-tests/server/http"
               "koya-tests/server/ui"
               "koya-tests/client")
  :perform (test-op (o c) (symbol-call :rove :run c :style :dot)))
