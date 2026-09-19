(defpackage #:koya-server/pages/s/<space>/m/<model>/index
  (:use #:cl #:hsx)
  (:import-from #:jingle #:set-response-status)
  (:import-from #:koya/core/schema #:model-kind #:model-fields #:field-name #:field-type)
  (:import-from #:koya/core/json #:json-null)
  (:import-from #:koya-server/db/schema-store #:find-model)
  (:import-from #:koya-server/db/contents
                #:list-contents #:find-object-content #:content-id #:content-status #:content-updated-at #:content-data)
  (:import-from #:koya-server/lib/query #:parse-query)
  (:import-from #:koya-server/lib/http #:path-param)
  (:import-from #:koya-server/lib/page
                #:with-owner #:set-title #:redirect-to #:~layout #:~status-badge #:~empty-state #:content-url #:model-url)
  (:export #:@get))
(in-package #:koya-server/pages/s/<space>/m/<model>/index)

(defun title-field (model)
  (find-if (lambda (f) (member (field-type f) '(:text :slug))) (model-fields model)))

(defun content-title (content model)
  (let* ((field (title-field model))
         (data (content-data content :draft t))
         (value (and field data (gethash (field-name field) data))))
    (if (and value (not (eq value json-null)) (stringp value) (plusp (length value)))
        value
        (content-id content))))

(defun @get (params)
  (with-owner
    (let* ((space (path-param params :space))
           (model-name (path-param params :model))
           (model (find-model space model-name)))
      (cond ((null model)
             (set-response-status 404)
             (hsx (~layout :space space (h1 :class "text-xl font-bold" "Model not found"))))
            ((eq (model-kind model) :object)
             (let ((content (find-object-content space model-name)))
               (redirect-to (content-url space model-name (if content (content-id content) "new")) 302)))
            (t
             (set-title (format nil "~a · ~a · koya" model-name space))
             (multiple-value-bind (contents total)
                 (list-contents space model-name model
                                (parse-query (list (cons "limit" "100") (cons "orders" "-updatedAt")))
                                :status :all)
               (hsx
                (~layout :space space :crumbs (list (cons model-name nil))
                  (div :class "mb-6 flex items-center justify-between"
                    (h1 :class "text-2xl font-bold" model-name
                      (span :class "ml-3 text-base font-normal text-muted" (format nil "~a content~:p" total)))
                    (a :href (content-url space model-name "new") :class "btn btn-primary" "New content"))
                  (if (null contents)
                      (hsx (~empty-state "No contents yet."))
                      (hsx (table :class "w-full text-sm"
                             (thead (tr :class "text-left text-muted"
                                      (th :class "py-2" "Title") (th "Status") (th "Updated")))
                             (tbody :class "divide-y divide-line"
                               (loop :for content :in contents :collect
                                 (hsx (tr
                                        (td :class "py-2"
                                          (a :href (content-url space model-name (content-id content))
                                             :class "font-medium hover:underline"
                                             (content-title content model)))
                                        (td (~status-badge :status (content-status content)))
                                        (td :class "text-muted" (content-updated-at content)))))))))))))))))
