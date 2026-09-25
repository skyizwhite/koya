(defpackage #:koya-server/web/presenters
  (:use #:cl)
  (:import-from #:koya/core/json #:jobject #:json-null #:to-json)
  (:import-from #:koya/core/schema #:model-fields #:field-name #:field-type)
  (:import-from #:koya/core/diff #:change->jobject)
  (:import-from #:koya-server/domain/content
                #:content-id #:content-status #:content-published #:content-draft
                #:content-draft-key #:content-created-at #:content-updated-at
                #:content-published-at #:content-revised-at)
  (:import-from #:koya-server/domain/media
                #:media #:media-id #:media-space #:media-filename #:media-mime #:media-size
                #:media-width #:media-height #:media-alt #:media-created-at #:media-file-name)
  (:import-from #:koya-server/usecases/contents/delivery
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
(in-package #:koya-server/web/presenters)

;;; What koya's answers are made of on the wire: a content and a media as the
;;; delivery API and webhooks carry them, and a content as the admin API shows
;;; it. Use cases hand over what they found; the names, the nulls and the URLs
;;; are decided here.

;;; --- Media ----------------------------------------------------------------------

(defun media-url (media &key (absolute t))
  "Where MEDIA is served: /media/{space}/{id}.{ext}, from the public URL unless
ABSOLUTE is NIL, as a page of this server needs it."
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

;;; --- A delivered content ------------------------------------------------------

(defun present-value (value)
  "A value of delivered data as the wire carries it."
  (typecase value
    (media (media->jobject value))
    (delivered (delivered->jobject value))
    ((and vector (not string)) (map 'vector #'present-value value))
    (t value)))

(defun absolutize-richtext (object model)
  "Destructively prefix /media/ paths inside richtext fields with the public URL:
the HTML is rendered by other sites, where a relative path would point at them."
  (let ((base (string-right-trim "/" (public-url))))
    (dolist (field (model-fields model) object)
      (when (eq (field-type field) :richtext)
        (let ((value (gethash (field-name field) object)))
          (when (stringp value)
            (setf (gethash (field-name field) object)
                  (regex-replace-all "(src|href)=\"/media/" value (format nil "\\1=\"~a/media/" base)))))))))

(defun select-fields (object fields)
  (if (null fields)
      object
      (let ((out (make-hash-table :test 'equal)))
        (dolist (name fields)
          (multiple-value-bind (v found) (gethash name object)
            (when found (setf (gethash name out) v))))
        out)))

(defun delivered->jobject (delivered &key fields)
  "DELIVERED as the delivery API and webhooks carry it: its data, with the system
fields, media and embedded contents as objects, and richtext pointing at this
server. FIELDS, when given, names the keys kept."
  (let ((content (delivered-content delivered))
        (object (make-hash-table :test 'equal)))
    (maphash (lambda (k v) (setf (gethash k object) (present-value v))) (delivered-data delivered))
    (setf (gethash "id" object) (content-id content)
          (gethash "createdAt" object) (content-created-at content)
          (gethash "updatedAt" object) (content-updated-at content)
          (gethash "publishedAt" object) (or (content-published-at content) json-null)
          (gethash "revisedAt" object) (or (content-revised-at content) json-null))
    (absolutize-richtext object (delivered-model delivered))
    (select-fields object fields)))

(defmethod webhook-payload (space model id event old new)
  (to-json (jobject "space" space
                    "model" model
                    "id" id
                    "event" (string-downcase (symbol-name event))
                    "contents" (jobject "old" (if old (delivered->jobject old) json-null)
                                        "new" (if new (delivered->jobject new) json-null)))))

;;; --- The admin API ------------------------------------------------------------

(defun copy-object (object)
  (let ((out (make-hash-table :test 'equal)))
    (maphash (lambda (k v) (setf (gethash k out) v)) object)
    out))

(defun admin-content->jobject (content)
  "A content with its status, both versions of its data and its metadata."
  (flet ((data (object) (and object (copy-object object))))
    (jobject "id" (content-id content)
             "status" (content-status content)
             "published" (or (data (content-published content)) json-null)
             "draft" (or (data (content-draft content)) json-null)
             "draftKey" (or (content-draft-key content) json-null)
             "createdAt" (content-created-at content)
             "updatedAt" (content-updated-at content)
             "publishedAt" (or (content-published-at content) json-null)
             "revisedAt" (or (content-revised-at content) json-null))))

(defun changes->jarray (changes)
  "A deploy's CHANGES, as core/diff makes them, for an answer."
  (map 'vector #'change->jobject changes))
