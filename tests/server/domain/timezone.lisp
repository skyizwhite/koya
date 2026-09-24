(defpackage #:koya-tests/server/domain/timezone
  (:use #:cl #:rove)
  (:import-from #:koya-server/domain/timezone
                #:find-timezone #:timezone-name-p #:timezone-names #:format-local
                #:iso->local-input #:local-input->iso)
  (:import-from #:local-time #:+utc-zone+))
(in-package #:koya-tests/server/domain/timezone)

;;; Conversions with an explicit zone; the display zone (a setting) is covered by
;;; the UI tests. Asia/Tokyo has no daylight saving, so the offset is always +09:00.

(deftest utc
  (ok (eq (find-timezone "UTC") +utc-zone+))
  (ok (eq (find-timezone "utc") +utc-zone+) "case does not matter for UTC")
  (ok (timezone-name-p "UTC"))
  (ng (timezone-name-p "Mars/Olympus_Mons"))
  (ng (timezone-name-p nil))
  (ok (string= (first (timezone-names)) "UTC"))
  (ok (string= (format-local "2026-09-20T05:04:03.123Z" :timezone +utc-zone+) "2026-09-20 05:04 UTC"))
  (ok (string= (iso->local-input "2026-09-20T05:04:03.123Z" :timezone +utc-zone+) "2026-09-20T05:04"))
  (ok (string= (local-input->iso "2026-09-20T05:04" :timezone +utc-zone+) "2026-09-20T05:04:00.000Z"))
  (ok (string= (local-input->iso "2026-09-20T05:04:09" :timezone +utc-zone+) "2026-09-20T05:04:09.000Z") "seconds kept")
  (ok (string= (local-input->iso "not a time" :timezone +utc-zone+) "not a time") "left for validation to reject")
  (ok (string= (format-local "garbage" :timezone +utc-zone+) "garbage"))
  (ok (string= (format-local nil :timezone +utc-zone+) "")))

(deftest tokyo
  (let ((tokyo (find-timezone "Asia/Tokyo")))
    (if (null tokyo)
        (skip "no zone database on this machine")
        (progn
          (ok (member "Asia/Tokyo" (timezone-names) :test #'string=))
          (ok (notany (lambda (n) (search "posix/" n)) (timezone-names)) "posix/ copies are not offered")
          (ok (string= (format-local "2026-09-20T05:04:03.123Z" :timezone tokyo) "2026-09-20 14:04 JST"))
          (ok (string= (iso->local-input "2026-09-20T23:30:00.000Z" :timezone tokyo) "2026-09-21T08:30") "crosses midnight")
          (ok (string= (local-input->iso "2026-09-21T08:30" :timezone tokyo) "2026-09-20T23:30:00.000Z"))
          (ok (string= (iso->local-input (local-input->iso "2026-09-20T10:00" :timezone tokyo) :timezone tokyo)
                       "2026-09-20T10:00")
              "round trip")))))
