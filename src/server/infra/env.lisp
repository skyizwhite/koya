(defpackage #:koya-server/infra/env
  (:use #:cl)
  (:import-from #:cl-dotenv
                #:load-env)
  (:import-from #:koya-server/usecases/ports/config
                #:public-url #:owner-secret #:dev-mode-p)
  (:import-from #:quri #:uri #:uri-scheme #:uri-host #:uri-error)
  (:export #:env
           #:setting-error
           #:setting-error-problems
           #:check-settings
           #:koya-env
           #:db-path
           #:media-dir
           #:archive-dir
           #:server-port))
(in-package #:koya-server/infra/env)

(let ((env-path "./.env"))
  (when (probe-file env-path)
    (load-env env-path)))

(defun env (name &optional default)
  (let ((value (uiop:getenv name)))
    (if (or (null value) (string= value "")) default value)))

(defun koya-env () (env "KOYA_ENV" "production"))
(defmethod dev-mode-p () (string= (koya-env) "dev"))
(defmethod owner-secret () (env "KOYA_SECRET" ""))
(defun db-path () (env "KOYA_DB_PATH" "./data/koya.db"))
(defun media-dir () (env "KOYA_MEDIA_DIR" "./data/media"))
(defun archive-dir ()
  (merge-pathnames "archives/" (uiop:pathname-directory-pathname (db-path))))
(defun server-port () (parse-integer (env "KOYA_PORT" "3100")))
(defmethod public-url () (env "KOYA_BASE_URL"))

(define-condition setting-error (error)
  ((problems :initarg :problems :reader setting-error-problems))
  (:report (lambda (condition stream)
             (format stream "~{~a~^~%~}" (setting-error-problems condition)))))

(defun port-problem ()
  (let* ((value (env "KOYA_PORT" "3100"))
         (port (parse-integer value :junk-allowed t)))
    (unless (and port (= (length (princ-to-string port)) (length value)) (<= 1 port 65535))
      (format nil "KOYA_PORT must be a port number from 1 to 65535, not ~s" value))))

(defun base-url-problem ()
  (let ((value (env "KOYA_BASE_URL")))
    (cond ((null value)
           "KOYA_BASE_URL is not set: give the URL the server is reached at, such as https://cms.example.com")
          ((not (let ((uri (handler-case (uri value) (uri-error () nil))))
                  (and uri (member (uri-scheme uri) '("http" "https") :test #'equal)
                       (plusp (length (or (uri-host uri) ""))))))
           (format nil "KOYA_BASE_URL must be an http or https URL, not ~s" value)))))

(defun check-settings ()
  (let ((problems (remove nil (list (base-url-problem) (port-problem)))))
    (when problems
      (error 'setting-error :problems problems))))
