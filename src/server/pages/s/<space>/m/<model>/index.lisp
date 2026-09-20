(defpackage #:koya-server/pages/s/<space>/m/<model>/index
  (:use #:cl #:hsx)
  (:import-from #:jingle #:set-response-status)
  (:import-from #:cl-ppcre #:regex-replace-all)
  (:import-from #:koya/core/schema
                #:model-kind #:model-name #:model-fields #:field-name #:field-type #:field-option #:space-model)
  (:import-from #:koya/core/json #:json-null)
  (:import-from #:koya-server/db/schema-store #:find-space)
  (:import-from #:koya-server/db/contents
                #:list-contents #:find-object-content #:content-id #:content-status #:content-data)
  (:import-from #:koya-server/lib/query #:parse-query #:make-query)
  (:import-from #:koya-server/lib/forms #:number->string)
  (:import-from #:koya-server/lib/http #:path-param)
  (:import-from #:koya-server/lib/page
                #:with-owner #:set-title #:redirect-to #:short-time #:content-label
                #:~layout #:~status-badge #:~empty-state #:~icon #:content-url #:model-url)
  (:export #:@get))
(in-package #:koya-server/pages/s/<space>/m/<model>/index)

(defparameter +preview-length+ 120
  "Longest field preview carried into the list, in characters.
A cell is two lines tall and ellipsises whatever does not fit, so this is only a
guard against putting a whole richtext body in the HTML: it sits above what the
widest column can show, which leaves the visible cut to the browser.")

(defparameter +column-widths+
  '((:text      . "min-w-32 max-w-56")
    (:textarea  . "min-w-36 max-w-64")
    (:richtext  . "min-w-36 max-w-64")
    (:number    . "min-w-16 max-w-24")
    (:boolean   . "min-w-16 max-w-20")
    (:date      . "min-w-24 max-w-28")
    (:datetime  . "min-w-32 max-w-40")
    (:select    . "min-w-24 max-w-36")
    (:media     . "min-w-24 max-w-36")
    (:reference . "min-w-32 max-w-48")
    (:slug      . "min-w-32 max-w-48"))
  "Bounds for a list column, per field type, as classes on the cell's inner box.
The minimum keeps a column readable and lets a wide model outgrow the page
rather than squeezing every column thin; the maximum stops one long text field
from taking the whole width. Between the two the preview sizes to its content.
They are deliberately tight: a preview gets two lines, so a narrow column still
shows a useful amount of text and more of the model fits on screen.")

(defun column-width (field)
  "Width bounds for FIELD's column, as classes on the cell's inner box."
  (or (cdr (assoc (field-type field) +column-widths+)) "min-w-24 max-w-48"))

(defparameter +row-height+ "h-14"
  "Two text-sm lines plus the cells' padding: the height of every row.
A preview is clamped to two lines, so no row outgrows it, and the height is set
on the row rather than the cell so that the cells' own middle alignment centres
a shorter preview — and the status badge and the chevron with it.")

(defun reference-labels (space model)
  "Field name -> hash of referenced id -> label, for every reference field of MODEL.
Components render lazily, so this is passed explicitly rather than bound dynamically."
  (let ((table (make-hash-table :test 'equal)))
    (dolist (field (model-fields model) table)
      (when (eq (field-type field) :reference)
        (let ((target (space-model space (field-option field :model)))
              (targets (make-hash-table :test 'equal)))
          (when target
            (dolist (content (list-contents (koya/core/schema:space-name space) (model-name target) target
                                            (make-query :limit 1000) :status :all))
              (setf (gethash (content-id content) targets) (content-label content target))))
          (setf (gethash (field-name field) table) targets))))))

(defun reference-label (field id ref-labels)
  (let ((table (and ref-labels (gethash (field-name field) ref-labels))))
    (or (and table (stringp id) (gethash id table)) id)))

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

(defun scalar-preview (field value ref-labels)
  "Preview of one non-empty VALUE of FIELD as plain text. LABELS resolves references."
  (case (field-type field)
    (:richtext (strip-html value))
    (:datetime (short-time value))
    (:boolean (if value "Yes" "No"))
    (:number (if (realp value) (number->string value) (princ-to-string value)))
    (:reference (collapse-whitespace (princ-to-string (reference-label field value ref-labels))))
    (t (collapse-whitespace (princ-to-string value)))))

(defun field-preview (field data ref-labels)
  "Plain-text preview of FIELD in DATA, or NIL when the field is empty."
  (let ((value (and data (gethash (field-name field) data))))
    (cond ((eq value json-null) nil)
          ((eq (field-type field) :boolean)
           ;; a stored false is NIL, so only a missing key is "empty"
           (and data (nth-value 1 (gethash (field-name field) data))
                (scalar-preview field value ref-labels)))
          ((null value) nil)
          ((and (vectorp value) (not (stringp value)))
           (and (plusp (length value))
                (truncate-text (format nil "~{~a~^, ~}"
                                       (map 'list (lambda (v) (scalar-preview field v ref-labels)) value)))))
          ((and (stringp value) (zerop (length value))) nil)
          (t (truncate-text (scalar-preview field value ref-labels))))))

(defcomp ~preview-cell (&key field content ref-labels)
  (let ((preview (field-preview field (content-data content :draft t) ref-labels)))
    (hsx (td :class (clsx "py-2 pr-4" (if preview "" "text-muted"))
           (div :class (clsx "line-clamp-2" (column-width field)) (or preview "—"))))))

(defun @get (params)
  (with-owner
    (let* ((space (path-param params :space))
           (model-name (path-param params :model))
           (space-object (find-space space))
           (model (and space-object (space-model space-object model-name))))
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
               (let ((fields (model-fields model))
                     (ref-labels (reference-labels space-object model)))
                 (hsx
                  (~layout :space space :crumbs (list (cons model-name nil))
                    (div :class "mb-6 flex items-center justify-between"
                      (h1 :class "text-2xl font-bold" model-name
                        (span :class "ml-3 text-base font-normal text-muted" (format nil "~a content~:p" total)))
                      (a :href (content-url space model-name "new") :class "btn btn-primary"
                         (~icon :name :plus) "New content"))
                    (if (null contents)
                        (hsx (~empty-state "No contents yet."))
                        (hsx (div :class "overflow-x-auto rounded-md border border-line bg-panel"
                               (table :class "w-full text-sm"
                                 (thead (tr :class "border-b border-line text-left text-muted"
                                          (th :class "py-2 pl-4 pr-4 font-medium whitespace-nowrap" "status")
                                          (loop :for field :in fields :collect
                                            (hsx (th :class "py-2 pr-4 font-medium"
                                                   (div :class (clsx "truncate" (column-width field)) (field-name field)))))
                                          (th)))
                                 (tbody :class "divide-y divide-line"
                                   (loop :for content :in contents :collect
                                     ;; the whole row opens the editor (see koya-editor.js)
                                     (hsx (tr :class (clsx "group cursor-pointer transition hover:bg-base" +row-height+)
                                              :data-href (content-url space model-name (content-id content))
                                              :tabindex "0" :role "link"
                                            (td :class "py-2 pl-4 pr-4 whitespace-nowrap"
                                              (~status-badge :status (content-status content)))
                                            (loop :for field :in fields :collect
                                              (hsx (~preview-cell :field field :content content :ref-labels ref-labels)))
                                            (td :class "py-2 pl-4 pr-4 text-right text-muted group-hover:text-accent" "›"))))))))))))))))))
