(defpackage #:koya-server/pages/s/<space>/m/<model>/index
  (:use #:cl #:hsx)
  (:import-from #:jingle #:set-response-status)
  (:import-from #:cl-ppcre #:regex-replace-all)
  (:import-from #:koya/core/schema #:model-kind #:model-fields #:field-name #:field-type)
  (:import-from #:koya/core/json #:json-null)
  (:import-from #:koya-server/db/schema-store #:find-model)
  (:import-from #:koya-server/db/contents
                #:list-contents #:find-object-content #:content-id #:content-status #:content-data)
  (:import-from #:koya-server/lib/query #:parse-query)
  (:import-from #:koya-server/lib/http #:path-param)
  (:import-from #:koya-server/lib/page
                #:with-owner #:set-title #:redirect-to #:short-time #:~layout #:~status-badge #:~empty-state
                #:content-url #:model-url)
  (:export #:@get))
(in-package #:koya-server/pages/s/<space>/m/<model>/index)

(defparameter +preview-length+ 60
  "Longest field preview shown in the list, in characters.")

(defun collapse-whitespace (string)
  (string-trim " " (regex-replace-all "\\s+" string " ")))

(defun strip-html (html)
  "Plain text of HTML: tags dropped, block boundaries become spaces, common entities decoded."
  (let ((text (regex-replace-all "<[^>]*>" html " ")))
    (dolist (pair '(("&nbsp;" . " ") ("&lt;" . "<") ("&gt;" . ">") ("&quot;" . "\"") ("&#39;" . "'") ("&amp;" . "&")))
      (setf text (regex-replace-all (car pair) text (cdr pair))))
    (collapse-whitespace text)))

(defun truncate-text (string &optional (limit +preview-length+))
  (if (> (length string) limit)
      (format nil "~a…" (subseq string 0 limit))
      string))

(defun scalar-preview (field value)
  "Preview of one non-empty VALUE of FIELD as plain text."
  (case (field-type field)
    (:richtext (strip-html value))
    (:datetime (short-time value))
    (:boolean (if value "Yes" "No"))
    (t (collapse-whitespace (princ-to-string value)))))

(defun field-preview (field data)
  "Plain-text preview of FIELD in DATA, or NIL when the field is empty."
  (let ((value (and data (gethash (field-name field) data))))
    (cond ((eq value json-null) nil)
          ((eq (field-type field) :boolean)
           ;; a stored false is NIL, so only a missing key is "empty"
           (and data (nth-value 1 (gethash (field-name field) data))
                (scalar-preview field value)))
          ((null value) nil)
          ((and (vectorp value) (not (stringp value)))
           (and (plusp (length value))
                (truncate-text (format nil "~{~a~^, ~}"
                                       (map 'list (lambda (v) (scalar-preview field v)) value)))))
          ((and (stringp value) (zerop (length value))) nil)
          (t (truncate-text (scalar-preview field value))))))

(defcomp ~preview-cell (&key field content)
  (let ((preview (field-preview field (content-data content :draft t))))
    (hsx (td :class (clsx "py-2 pr-4" (if preview "" "text-muted")) (or preview "—")))))

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
                                (parse-query (list (cons "limit" "100") (cons "orders" "-createdAt")))
                                :status :all)
               (let ((fields (model-fields model)))
                 (hsx
                  (~layout :space space :crumbs (list (cons model-name nil))
                    (div :class "mb-6 flex items-center justify-between"
                      (h1 :class "text-2xl font-bold" model-name
                        (span :class "ml-3 text-base font-normal text-muted" (format nil "~a content~:p" total)))
                      (a :href (content-url space model-name "new") :class "btn btn-primary" "New content"))
                    (if (null contents)
                        (hsx (~empty-state "No contents yet."))
                        (hsx (div :class "overflow-x-auto"
                               (table :class "w-full text-sm"
                                 (thead (tr :class "text-left text-muted"
                                          (loop :for field :in fields :collect
                                            (hsx (th :class "py-2 pr-4 font-medium" (field-name field))))
                                          (th :class "py-2 font-medium" "Status")
                                          (th)))
                                 (tbody :class "divide-y divide-line"
                                   (loop :for content :in contents :collect
                                     ;; the whole row opens the editor (see koya-editor.js)
                                     (hsx (tr :class "group cursor-pointer transition hover:bg-accent/5"
                                              :data-href (content-url space model-name (content-id content))
                                              :tabindex "0" :role "link"
                                            (loop :for field :in fields :collect
                                              (hsx (~preview-cell :field field :content content)))
                                            (td :class "py-2" (~status-badge :status (content-status content)))
                                            (td :class "py-2 pl-4 text-right text-muted group-hover:text-accent" "›"))))))))))))))))))
