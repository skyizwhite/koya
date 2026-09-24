(defpackage #:koya-server/usecases/keys
  (:use #:cl)
  (:import-from #:koya-server/usecases/ports/keys
                #:create-delivery-key #:list-delivery-keys #:delete-delivery-key #:space-for-delivery-key
                #:create-management-key #:list-management-keys #:delete-management-key
                #:space-for-management-key #:management-key-label)
  (:import-from #:koya-server/usecases/ports/spaces
                #:space-webhook-secret #:rotate-webhook-secret)
  (:export #:create-delivery-key
           #:list-delivery-keys
           #:delete-delivery-key
           #:space-for-delivery-key
           #:create-management-key
           #:list-management-keys
           #:delete-management-key
           #:space-for-management-key
           #:management-key-label
           #:space-webhook-secret
           #:rotate-webhook-secret))
(in-package #:koya-server/usecases/keys)

;;; Four keys, three kinds of callers:
;;;  - the owner secret (KOYA_SECRET) logs into the admin UI (usecases/auth)
;;;  - a management key drives the admin API for one space, and reaches nothing
;;;    outside it
;;;  - a delivery key reads one space's published content
;;;  - the webhook secret is the one koya sends, not one it checks
;;;
;;; What there is to do with them is what the store does, so this names it.
