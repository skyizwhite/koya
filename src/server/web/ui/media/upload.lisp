(defpackage #:koya-server/web/ui/media/upload
  (:use #:cl #:hsx)
  (:import-from #:ningle-actions #:defaction)
  (:import-from #:koya-server/domain/media #:+max-upload-bytes+)
  (:import-from #:koya-server/domain/errors #:koya-error)
  (:import-from #:koya-server/usecases/spaces #:find-space)
  (:import-from #:koya-server/usecases/media #:store-upload)
  (:import-from #:koya-server/web/lib/http #:uploaded-files #:param)
  (:import-from #:koya-server/web/ui/icon #:~icon)
  (:import-from #:koya-server/web/ui/toast #:action-refusal #:action-refused)
  (:export #:~upload-form
           #:upload-media))
(in-package #:koya-server/web/ui/media/upload)

(defun limit-message ()
  (format nil "Images are limited to ~a MB each." (floor +max-upload-bytes+ (* 1024 1024))))

(defcomp ~upload-form (&key space redraw search hint class)
  (hsx
   (form :n-scope "koya.uploader(this)" :n-on-change "upload(e.target)"
         :data-upload-url (upload-media :space space)
         :data-upload-limit (princ-to-string +max-upload-bytes+)
         :data-upload-limit-message (limit-message)
         :data-upload-redraw redraw
         :data-upload-search search
         :class (clsx "flex flex-wrap items-center gap-3 rounded-md border border-dashed border-line p-3 text-sm" class)
     (label :class "btn" (~icon :name :upload) "Upload"
       (input :type "file" :name "file" :accept "image/png,image/jpeg,image/gif,image/webp"
              :multiple t :class "hidden" :n-bind-disabled "busy"))
     (span :class "text-muted" hint)
     (dialog :id "upload-progress" :closedby "any" :class "koya-dialog max-w-sm" :n-ref "dialog"
       (div :class "flex items-center justify-between gap-4 border-b border-line px-4 py-3"
         (h2 :class "font-semibold" "Upload")
         (button :type "button" :commandfor "upload-progress" :command "close" :class "btn btn-icon" :aria-label "Close"
           (~icon :name :close)))
       (div :class "px-4 py-4"
         (progress :class "w-full" :max "1" :value "0" :n-bind-max "total || 1" :n-bind-value "sent")
         (p :class "mt-1 text-xs text-muted" :n-bind-textcontent "status"))
       (p :class "whitespace-pre-line px-4 pb-3 text-sm text-danger" :hidden t
          :n-bind-hidden "!error" :n-bind-textcontent "error")
       (div :class "flex justify-end gap-2 border-t border-line px-4 py-3"
         (button :type "button" :commandfor "upload-progress" :command "close" :class "btn" :n-bind-disabled "busy"
           "Close"))))))

(defaction upload-media :post (params)
  (let ((space (param params "space"))
        (files (uploaded-files params "file")))
    (cond ((not (and space (find-space space))) (action-refusal "Space not found." 404))
          ((/= (length files) 1) (action-refusal "Send one image at a time." 400))
          (t (destructuring-bind (bytes filename &rest type) (first files)
               (declare (ignore type))
               (handler-case (progn (store-upload space bytes :filename filename) (hsx (<>)))
                 (koya-error (e) (action-refused e))))))))
