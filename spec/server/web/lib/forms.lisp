(defpackage #:koya-spec/server/web/lib/forms
  (:use #:cl #:rove)
  (:import-from #:koya-server/web/lib/forms #:form->data)
  (:import-from #:koya-core/schema #:make-field #:make-model #:make-schema #:make-custom-field #:schema-model)
  (:import-from #:koya-core/json #:jget))
(in-package #:koya-spec/server/web/lib/forms)

(defparameter +crlf+ (format nil "~C~C" #\Return #\Newline))

(defun lines (&rest lines)
  (format nil "~{~a~^~%~}" lines))

(deftest a-textarea-is-read-as-it-was-written
  (let ((model (make-model "note" :list (list (make-field :text :textarea) (make-field :title :text)))))
    (flet ((read-field (name value)
             (multiple-value-list (gethash name (form->data model (list (cons (format nil "f-~a" name) value)))))))
      (ok (equal (read-field "text" (format nil "a~ab" +crlf+)) (list (lines "a" "b") t))
          "the CRLF a browser sends is the line break it was given")
      (ok (equal (read-field "text" (format nil "  indented~a" +crlf+)) (list (format nil "  indented~%") t))
          "and nothing around the text is trimmed")
      (ok (equal (read-field "text" (format nil " ~a " +crlf+)) (list nil nil))
          "but whitespace alone is no value")
      (ok (equal (read-field "title" "  Title  ") (list "Title" t))
          "a one-line text is trimmed as before"))))

(deftest a-custom-field-is-read-from-its-fields
  (let ((model (schema-model (make-schema :custom-fields (list (make-custom-field "card" (list (make-field :title :text)
                                                                                                (make-field :shown :boolean)
                                                                                                (make-field :rank :number))))
                                          :models (list (make-model "page" :list (list (make-field :card :custom :custom-field "card")))))
                             "page")))
    (let ((card (gethash "card" (form->data model '(("f-card.title" . " Hi ") ("f-card.shown" . "on") ("f-card.rank" . "2"))))))
      (ok (string= (jget card "title") "Hi") "each field inside is read as it is at the top")
      (ok (eq (jget card "shown") t))
      (ok (= (jget card "rank") 2)))
    (ok (null (nth-value 1 (gethash "card" (form->data model '(("f-card.title" . " ")))))) "and all blank is no value")))
