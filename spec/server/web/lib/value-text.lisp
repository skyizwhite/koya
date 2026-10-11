(defpackage #:koya-spec/server/web/lib/value-text
  (:use #:cl #:rove)
  (:import-from #:koya-server/web/lib/value-text #:value-text)
  (:import-from #:koya-core/schema #:make-field #:make-model #:make-schema #:make-custom-field #:schema-model
                #:model-field)
  (:import-from #:koya-core/json #:jobject #:json-null))
(in-package #:koya-spec/server/web/lib/value-text)

(defun page-model ()
  (schema-model (make-schema :custom-fields (list (make-custom-field "card" (list (make-field :title :text)
                                                                                  (make-field :body :richtext)))
                                                  (make-custom-field "flag" (list (make-field :on :boolean)
                                                                                  (make-field :rank :number))))
                             :models (list (make-model "page" :list (list (make-field :card :custom :custom-field "card")
                                                                          (make-field :blocks :repeater :custom-fields '(card flag))))))
                "page"))

(defun label (field id)
  (declare (ignore field))
  (format nil "Label of ~a" id))

(defun text (field value &optional (found t))
  (value-text field value found #'label))

(deftest a-value-reads-as-text
  (testing "rich text reads as its text, every character reference decoded"
    (ok (string= (text (make-field :body :richtext) "<p>It&#8217;s &#x2014; <b>bold</b> &amp; more</p>")
                 "It’s — bold & more"))
    (ok (null (text (make-field :body :richtext) "<p></p><img src=\"a.png\">")) "one with no text in it is none")
    (ok (string= (text (make-field :body :richtext) 42) "42") "and one that is not a string, as an old version may hold, is printed"))
  (testing "a scalar"
    (ok (string= (text (make-field :count :number) 3) "3"))
    (ok (string= (text (make-field :title :text) "Hello") "Hello"))
    (ok (string= (text (make-field :shown :boolean) t) "Yes"))
    (ok (string= (text (make-field :shown :boolean) nil) "No") "false is a value")
    (ok (null (text (make-field :shown :boolean) nil nil)) "but a box never set is none")
    (ok (null (text (make-field :shown :boolean) json-null)) "and so is null"))
  (testing "an id reads as the page's label for it"
    (ok (string= (text (make-field :related :reference :model "page") "01A") "Label of 01A"))
    (ok (string= (text (make-field :cover :media) "01M") "Label of 01M"))
    (ok (string= (text (make-field :related :reference :model "page" :many t) (vector "01A" "01B"))
                 "Label of 01A, Label of 01B")
        "many, one after another"))
  (testing "nothing is none"
    (ok (null (text (make-field :title :text) "")))
    (ok (null (text (make-field :title :text) "Hello" nil)) "a value the data does not hold")
    (ok (null (text (make-field :title :text) json-null)))
    (ok (null (text (make-field :labels :select :options '("a") :many t) (vector))))))

(deftest a-custom-field-and-a-repeater-read-field-by-field
  (let* ((model (page-model))
         (card (model-field model "card"))
         (blocks (model-field model "blocks")))
    (ok (string= (text card (jobject "title" "Hi" "body" "<p>Rich&#8217;s</p>"))
                 (format nil "title: Hi~%body: Rich’s"))
        "a custom field's fields by name, rich text among them as text")
    (ok (null (text card (jobject "title" "" "body" "<p></p>"))) "one with nothing in it is none")
    (ok (string= (text blocks (vector (jobject "fieldId" "card" "title" "Hi")
                                      (jobject "fieldId" "flag" "on" t "rank" 2)))
                 (format nil "card: title: Hi~%flag: on: Yes; rank: 2"))
        "a repeater row by row, each by its custom field")
    (ok (null (text blocks "not rows")) "a repeater that holds no rows is none")))
