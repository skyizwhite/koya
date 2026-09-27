(defpackage #:koya-spec/server/domain/address
  (:use #:cl #:rove)
  (:import-from #:koya-server/domain/address
                #:address-reach #:addresses-reach #:address-string))
(in-package #:koya-spec/server/domain/address)

(defun v6 (&rest groups)
  (coerce (loop :for g :in groups :append (list (ash g -8) (logand g #xff))) 'vector))

(deftest reach-of-one-address
  (testing "never sent to: link-local, unspecified, multicast and reserved"
    (dolist (a (list #(169 254 169 254) #(0 0 0 0) #(0 1 2 3) #(224 0 0 1) #(239 255 255 250)
                     #(240 0 0 1) #(255 255 255 255)
                     (v6 0 0 0 0 0 0 0 0) (v6 #xfe80 0 0 0 0 0 0 1) (v6 #xff02 0 0 0 0 0 0 1)
                     (v6 0 0 0 0 0 #xffff #xa9fe #xa9fe)))
      (ok (eq (address-reach a) :forbidden) (format nil "~a" a))))
  (testing "never sent to: the metadata addresses outside link-local"
    (dolist (a (list #(100 100 100 200) #(168 63 129 16) (v6 #xfd00 #xec2 0 0 0 0 0 #x254)))
      (ok (eq (address-reach a) :forbidden) (format nil "~a" a))))
  (testing "an IPv4 address carried in IPv6 is judged as itself"
    (ok (eq (address-reach (v6 #x64 #xff9b 0 0 0 0 #xa9fe #xa9fe)) :forbidden) "NAT64")
    (ok (eq (address-reach (v6 #x64 #xff9b 1 0 0 0 #xa9fe #xa9fe)) :forbidden) "local-use NAT64")
    (ok (eq (address-reach (v6 0 0 0 0 0 0 0 1)) :internal) "::1 is loopback, not an IPv4 address")
    (ok (eq (address-reach (v6 #x2002 #xa9fe #xa9fe 0 0 0 0 1)) :forbidden) "6to4")
    (ok (eq (address-reach (v6 #x64 #xff9b 0 0 0 0 #x0a00 1)) :internal))
    (ok (eq (address-reach (v6 #x2002 #x0808 #x0808 0 0 0 0 1)) :public)))
  (testing "internal: loopback and private"
    (dolist (a (list #(127 0 0 1) #(127 255 0 9) #(10 1 2 3) #(172 16 0 1) #(172 31 255 255)
                     #(192 168 1 1) #(100 64 0 1)
                     (v6 0 0 0 0 0 0 0 1) (v6 #xfd00 0 0 0 0 0 0 1) (v6 #xfc00 0 0 0 0 0 0 1)
                     (v6 0 0 0 0 0 #xffff #x7f00 1)))
      (ok (eq (address-reach a) :internal) (format nil "~a" a))))
  (testing "public: everything else"
    (dolist (a (list #(93 184 216 34) #(172 32 0 1) #(172 15 255 255) #(192 169 0 1) #(100 128 0 1)
                     #(8 8 8 8) (v6 #x2606 #x4700 0 0 0 0 0 #x1111)))
      (ok (eq (address-reach a) :public) (format nil "~a" a)))))

(deftest reach-of-a-host
  (ok (null (addresses-reach '())) "a host that resolves to nothing has no reach")
  (ok (eq (addresses-reach (list #(8 8 8 8))) :public))
  (ok (eq (addresses-reach (list #(8 8 8 8) #(10 0 0 1))) :internal) "one internal address makes the host internal")
  (ok (eq (addresses-reach (list #(10 0 0 1) #(169 254 169 254))) :forbidden) "and one forbidden one forbids it"))

(deftest address-strings
  (ok (string= (address-string #(93 184 216 34)) "93.184.216.34"))
  (ok (string= (address-string (v6 #x2606 #x4700 0 0 0 0 0 #x1111)) "2606:4700:0:0:0:0:0:1111")))
