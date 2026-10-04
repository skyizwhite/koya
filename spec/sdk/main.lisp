(defpackage #:koya-spec/sdk/main
  (:use #:cl #:rove))
(in-package #:koya-spec/sdk/main)

(defparameter +site-api+
  '("DEFMODEL" "DEFWEBHOOKS" "WEBHOOK" "CURRENT-SCHEMA" "CLEAR-SCHEMA" "FIND-MODEL"
    "*BASE-URL*" "*SPACE*" "*DELIVERY-KEY*" "*MANAGEMENT-KEY*" "CONFIGURE"
    "PLAN" "DEPLOY" "PULL"
    "GET-LIST" "GET-LIST-CONTENT" "GET-OBJECT"
    "ADMIN-GET-LIST" "ADMIN-GET-LIST-CONTENT" "ADMIN-CREATE-LIST-CONTENT" "ADMIN-UPDATE-LIST-CONTENT"
    "ADMIN-DELETE-LIST-CONTENT" "ADMIN-PUBLISH-LIST-CONTENT" "ADMIN-UNPUBLISH-LIST-CONTENT"
    "ADMIN-DISCARD-LIST-CONTENT-DRAFT" "ADMIN-LIST-CONTENT-DRAFT-KEY"
    "ADMIN-GET-OBJECT" "ADMIN-UPDATE-OBJECT" "ADMIN-PUBLISH-OBJECT" "ADMIN-UNPUBLISH-OBJECT"
    "ADMIN-DISCARD-OBJECT-DRAFT" "ADMIN-OBJECT-DRAFT-KEY"
    "LIST-MEDIA" "GET-MEDIA" "UPLOAD-MEDIA" "UPDATE-MEDIA" "DELETE-MEDIA"
    "LIST-DELIVERY-KEYS" "CREATE-DELIVERY-KEY" "DELETE-DELIVERY-KEY" "WEBHOOK-SECRET"
    "KOYA-ERROR" "KOYA-ERROR-STATUS" "KOYA-ERROR-CODE" "KOYA-ERROR-MESSAGE" "KOYA-ERROR-DETAILS"
    "NOW-ISO" "FORMAT-ISO" "PARSE-ISO" "MAKE-ULID"))

(deftest a-site-sees-its-api-and-nothing-else
  (let ((exported '()))
    (do-external-symbols (symbol :koya-sdk)
      (push (symbol-name symbol) exported))
    (ok (null (set-difference +site-api+ exported :test #'string=)) "all of it")
    (ok (null (set-difference exported +site-api+ :test #'string=)) "and nothing else")))

(defparameter +error-readers+
  '("KOYA-ERROR-STATUS" "KOYA-ERROR-CODE" "KOYA-ERROR-MESSAGE" "KOYA-ERROR-DETAILS"))

(deftest the-api-is-documented-where-a-site-reads-it
  (dolist (name (set-difference +site-api+ +error-readers+ :test #'string=))
    (let ((symbol (find-symbol name :koya-sdk)))
      (ok (or (documentation symbol 'function)
              (documentation symbol 'variable)
              (documentation symbol 'type))
          name)))
  (testing "the error's readers are named where the error is"
    (let ((documentation (documentation (find-symbol "KOYA-ERROR" :koya-sdk) 'type)))
      (dolist (name +error-readers+)
        (ok (search name documentation) name)))))
