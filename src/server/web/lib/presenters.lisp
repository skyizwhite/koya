(defpackage #:koya-server/web/lib/presenters
  (:use #:cl)
  (:import-from #:koya-core/json #:jobject #:json-null #:to-json)
  (:import-from #:koya-core/data #:array-p)
  (:import-from #:koya-core/case #:camel-key #:data->jvalue)
  (:import-from #:koya-core/schema
                #:model-fields #:field-name #:field-key #:field-type #:field-fields #:custom-field-fields
                #:row-kind #:row-fields)
  (:import-from #:koya-core/schema-json #:change->jobject)
  (:import-from #:koya-server/domain/content
                #:content-id #:content-status #:content-published #:content-draft
                #:content-published-p #:content-draft-p
                #:content-draft-key #:content-created-at #:content-updated-at
                #:content-published-at #:content-revised-at)
  (:import-from #:koya-server/domain/media
                #:media #:media-id #:media-space #:media-filename #:media-mime #:media-size
                #:media-width #:media-height #:media-alt #:media-created-at #:media-file-name)
  (:import-from #:koya-server/usecases/delivery
                #:delivered #:delivered-content #:delivered-model #:delivered-data)
  (:import-from #:koya-server/usecases/ports/presenters
                #:webhook-payload)
  (:import-from #:koya-server/usecases/system
                #:public-url)
  (:import-from #:cl-ppcre
                #:regex-replace-all)
  (:export #:delivered->jobject
           #:media->jobject
           #:media-url
           #:admin-content->jobject
           #:changes->jarray))
(in-package #:koya-server/web/lib/presenters)

(defun media-url (media &key (absolute t))
  (let ((path (format nil "/media/~a/~a" (media-space media) (media-file-name media))))
    (if absolute
        (concatenate 'string (string-right-trim "/" (public-url)) path)
        path)))

(defun media->jobject (media)
  (jobject "id" (media-id media)
           "url" (media-url media)
           "filename" (media-filename media)
           "mime" (media-mime media)
           "size" (media-size media)
           "width" (or (media-width media) json-null)
           "height" (or (media-height media) json-null)
           "alt" (media-alt media)
           "createdAt" (media-created-at media)))

(defun present-value (value)
  (typecase value
    (media (media->jobject value))
    (delivered (delivered->jobject value))
    ((eql :null) json-null)
    ((satisfies array-p) (map 'vector #'present-value value))
    (cons (data->jvalue value))
    (t value)))

(defun absolute-richtext (html base)
  (regex-replace-all "(src|href)=\"/media/" html (format nil "\\1=\"~a/media/" base)))

(defun present-row (field row base)
  (multiple-value-bind (kind id) (row-kind field row)
    (if kind
        (let ((out (present-fields (custom-field-fields kind) (row-fields row) base)))
          (setf (gethash "fieldId" out) id)
          out)
        (present-value row))))

(defun present-field (field value base)
  (case (field-type field)
    (:custom (if (listp value) (present-fields (field-fields field) value base) (present-value value)))
    (:repeater (if (array-p value)
                   (map 'vector (lambda (row) (present-row field row base)) value)
                   (present-value value)))
    (:richtext (if (and base (stringp value)) (absolute-richtext value base) (present-value value)))
    (t (present-value value))))

(defun present-fields (fields data base)
  (let ((out (make-hash-table :test 'equal)))
    (loop :for (key value) :on data :by #'cddr
          :for field := (find key fields :key #'field-key)
          :do (setf (gethash (if field (field-name field) (camel-key key)) out)
                    (if field (present-field field value base) (present-value value))))
    out))

(defparameter +system-fields+ '("id" "createdAt" "updatedAt" "publishedAt" "revisedAt"))

(defun select-fields (object fields)
  (if (null fields)
      object
      (let ((out (make-hash-table :test 'equal)))
        (dolist (name (append +system-fields+ fields))
          (multiple-value-bind (v found) (gethash name object)
            (when found (setf (gethash name out) v))))
        out)))

(defun delivered->jobject (delivered &key fields)
  (let* ((content (delivered-content delivered))
         (model (delivered-model delivered))
         (object (present-fields (model-fields model) (delivered-data delivered)
                                 (string-right-trim "/" (public-url)))))
    (setf (gethash "id" object) (content-id content)
          (gethash "createdAt" object) (content-created-at content)
          (gethash "updatedAt" object) (content-updated-at content)
          (gethash "publishedAt" object) (or (content-published-at content) json-null)
          (gethash "revisedAt" object) (or (content-revised-at content) json-null))
    (select-fields object fields)))

(defmethod webhook-payload (space model id event old new &key changes)
  (let ((payload (jobject "space" space
                          "model" model
                          "id" (or id json-null)
                          "event" (string-downcase (symbol-name event))
                          "contents" (jobject "old" (if old (delivered->jobject old) json-null)
                                              "new" (if new (delivered->jobject new) json-null)))))
    (when changes
      (setf (gethash "changes" payload) (changes->jarray changes)))
    (to-json payload)))

(defun admin-content->jobject (content model)
  (flet ((data (present data) (if present (present-fields (model-fields model) data nil) json-null)))
    (jobject "id" (content-id content)
             "status" (content-status content)
             "published" (data (content-published-p content) (content-published content))
             "draft" (data (content-draft-p content) (content-draft content))
             "draftKey" (or (content-draft-key content) json-null)
             "createdAt" (content-created-at content)
             "updatedAt" (content-updated-at content)
             "publishedAt" (or (content-published-at content) json-null)
             "revisedAt" (or (content-revised-at content) json-null))))

(defun changes->jarray (changes)
  (map 'vector #'change->jobject changes))
