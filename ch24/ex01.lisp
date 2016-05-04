;; 24. Practical: Parsing Binary Files

; Binary Files

; Binary Format Basics

;(defun read-u2 (in)
;  (+ (* (read-byte in) 256) (read-byte in)))

(defun read-u2 (in)
  (let ((u2 0))
    (setf (ldb (byte 8 8) u2) (read-byte in))
    (setf (ldb (byte 8 0) u2) (read-byte in))
    u2))

(defun write-u2 (out value)
  (write-byte (ldb (byte 8 8) value) out)
  (write-byte (ldb (byte 8 0) value) out))



; Strings in Binary Files

(defconstant +null+ (code-char 0))

(defun read-null-terminated-ascii (in)
  (with-output-to-string (s)
    (loop for char = (code-char (read-byte in))
	 until (char= char +null+) do (write-char char s))))

(defun write-null-terminated-ascii (string out)
  (loop for char across string
       do (write-byte (char-code char) out))
  (write-byte (char-code +null+) out))




; Composite Structures

(defclass id3-tag ()
  ((identifier    :initarg :identifier    :accessor identifier)
   (major-version :initarg :major-version :accessor major-version)
   (revision      :initarg :revision      :accessor revision)
   (flags         :initarg :flags         :accessor flags)
   (size          :initarg :size          :accessor size)
   (frames        :initarg :frames        :accessor frames)))

(defun read-id3-tag (in)
  (let ((tag (make-instance 'id3-tag)))
    (with-slots (identifier major-version revision flags size frames) tag
      (setf identifier    (read-iso-8859-1-string in :length 3))
      (setf major-version (read-u1 in))
      (setf revision      (read-u1 in))
      (setf flags         (read-u1 in))
      (setf size          (read-id3-encoded-size in))
      (setf frames        (read-id3-frames in :tag-size size)))
    tag))



; Designing the Macros


;; (define-binary-class id3-tag
;;     ((file-identifier (iso-8859-1-string :length 3))
;;      (major-version u1)
;;      (revision      u1)
;;      (flags         u1)
;;      (size          id3-tag-size)
;;      (frames        (id3-frames :tag-size size))))



; Making the Dream a Reality

(in-package :cl-user)

(defpackage :com.gigamonkeys.binary-data
  (:use :common-lisp :com.gigamonkeys.macro-utilities)
  (:export :define-binary-class
	   :define-tagged-binary-class
	   :define-binary-type
	   :read-value
	   :write-value
	   :*in-progress-objects*
	   :parent-of-type
	   :current-binary-object
	   :+null+))


(defun as-keyword (sym) (intern (string sym) :keyword))

(defun slot->defclass-slot (spec)
  (let ((name (first spec)))
    `(,name :initarg ,(as-keyword name) :accessor ,name)))

;; (defmacro define-binary-class (name slots)
;;   `(defclass ,name ()
;;      ,(mapcar #'slot->defclass-slot slots)))




; Reading Binary Objects

(defgeneric read-value (type stream &key)
  (:documentation "Read a value of the given type from the stream."))

(defmethod read-value ((type (eql 'id3-tag)) in &key)
  (let ((object (make-instance 'id3-tag)))
    (with-slots (identifier major-version revision flags size frames) object
      (setf identifier    (read-value 'iso-8859-1-string in :length 3))
      (setf major-version (read-value 'u1 in))
      (setf revision      (read-value 'u1 in))
      (setf flags         (read-value 'u1 in))
      (setf size          (read-value 'id3-encoded-size in))
      (setf frames        (read-value 'id3-frames in :tag-size size)))
    object))

(defun slot->read-value (spec stream)
  (destructuring-bind (name (type &rest args)) (normalize-slot-spec spec)
    `(setf ,name (read-value ',type ,stream ,@args))))

(defun normalize-slot-spec (spec)
  (list (first spec) (mklist (second spec))))

(defun mklist (x) (if (listp x) x (list x)))

;; (defmethod define-binary-class (name slots)
;;   (with-gensyms (typevar objectvar streamvar)
;;     `(progn
;;        (defclass ,name ()
;; 	 ,(mapcar #'slot->defclass-slot slots))
       
;;        (defmethod read-value ((,typevar (eql ',name)) ,streamvar &key)
;; 	 (let ((,objectvar (make-instance ',name)))
;; 	   (with-slots ,(mapcar #'first slots) ,objectvar
;; 	     ,@(mapcar #'(lambda (x) (slot->read-value x streamvar)) slots))
;; 	   ,objectvar)))))




; Writing Binary Objects

(defgeneric write-value (type stream value &key)
  (:documentation "Write a value as the given type to the stream."))

(defun slot->write-value (spec stream)
  (destructuring-bind (name (type &rest args)) (normalize-slot-spec spec)
    `(write-value ',type ,stream ,name ,@args)))

(defmacro define-binary-class (name slots)
  (with-gensyms (typevar objectvar streamvar)
    `(progn
       (defclass ,name ()
	 ,(mapcar #'slot->defclass-slot slots))

       (defmethod read-value ((,typevar (eql ',name)) ,streamvar &key)
	 (let ((,objectvar (make-instance ',name)))
	   (with-slots ,(mapcar #'first slots) ,objectvar
	     ,@(mapcar #'(lambda (x) (slot->read-value x streamvar)) slots))
	   ,objectvar))

       (defmethod write-value ((,typevar (eql ',name)) ,streamvar ,objectvar &key)
	 (with-slots ,(mapcar #'first slots) ,objectvar
	   ,@(mapcar #'(lambda (x) (slot->write-value x streamvar)) slots))))))



; Adding Inheritance and Tagged Structures

(defgeneric read-object (object stream)
  (:method-combination progn :most-specific-last)
  (:documentation "Fill in the slots of object from stream."))

(defgeneric write-object (object stream)
  (:method-combination progn :most-specific-last)
  (:documentation "Write out the slots of object to the stream."))

(defmethod read-value ((type symbol) stream &key)
  (let ((object (make-instance type)))
    (read-object object stream)
    object))

(defmethod write-value ((type symbol) stream value &key)
  (assert (typep value type))
  (write-object value stream))

(defmacro define-binary-class (name superclasses slots)
  (with-gensyms (objectvar streamvar)
    `(progn
       (defclass ,name ,superclasses
	 ,(mapcar #'slot->defclass-slot slots))
       
       (defmethod read-object progn ((,objectvar ,name) ,streamvar)
		  (with-slots ,(mapcar #'first slots) ,objectvar
		    ,@(mapcar #'(lambda (x) (slot->read-value x streamvar)) slots)))
       
       (defmethod write-object progn ((,objectvar ,name) ,streamvar)
		  (with-slots ,(mapcar #'first slots) ,objectvar
		    ,@(mapcar #'(lambda (x) (slot->write-value x streamvar)) slots))))))



; Keeping Track of Inherited Slots

;; (define-binary-class generic-frame ()
;;   ((id (iso-8859-1-string :length 3))
;;    (size u3)
;;    (data (raw-bytes :bytes size))))

(defun direct-slots (name)
  (copy-list (get name 'slots)))

(defun inherited-slots (name)
  (loop for super in (get name 'superclasses)
       nconc (direct-slots super)
       nconc (inherited-slots super)))

(defun all-slots (name)
  (nconc (direct-slots name) (inherited-slots name)))

(defun new-class-all-slots (slots superclasses)
  (nconc (mapcan #'all-slots superclasses) (mapcar #'first slots)))

(defmacro define-binary-class (name (&rest superclasses) slots)
  (with-gensyms (objectvar streamvar)
    `(progn
       (eval-when (:compile-toplevel :load-toplevel :execute)
	 (setf (get ',name 'slots) ',(mapcar #'first slots))
	 (setf (get ',name 'superclasses) ',superclasses))

       (defclass ,name ,superclasses
	 ,(mapcar #'slot->defclass-slot slots))

       (defmethod read-object progn ((,objectvar ,name) ,streamvar)
		  (with-slots ,(new-class-all-slots slots superclasses) ,objectvar
		    ,@(mapcar #'(lambda (x) (slot->read-value x streamvar)) slots)))

       (defmethod write-object progn ((,objectvar ,name) ,streamvar)
		  (with-slots ,(new-class-all-slots slots superclasses) ,objectvar
		    ,@(mapcar #'(lambda (x) (slot->write-value x streamvar)) slots))))))



; Tagged Structures

(defmethod read-value ((type (eql 'id3-frame)) stream &key)
  (let ((id (read-value 'iso-8859-1-string stream :length 3))
	(size (read-value 'u3 stream)))
    (let ((object (make-instance (find-frame-class id) :id id :size size)))
      (read-object object stream)
      object)))

(defmacro define-generic-binary-class (name (&rest superclasses) slots read-method)
  (with-gensyms (objectvar streamvar)
    `(progn
       (eval-when (:compile-toplevel :load-toplevel :execute)
	 (setf (get ',name 'slots) ',(mapcar #'first slots))
	 (setf (get ',name 'superclasses) ',superclasses))
       
       (defclass ,name ,superclasses
	 ,(mapcar #'slot->defclass-slot slots))

       ,read-method

       (defmethod write-object progn ((,objectvar ,name) ,streamvar)
		  (declare (ignorable ,streamvar))
		  (with-slots ,(new-class-all-slots slots superclasses) ,objectvar
		    ,@(mapcar #'(lambda (x) (slot->write-value x streamvar)) slots))))))

(defmacro define-binary-class (name (&rest superclasses) slots)
  (with-gensyms (objectvar streamvar)
    `(define-generic-binary-class ,name ,superclasses ,slots
				  (defmethod read-object progn ((,objectvar ,name) ,streamvar)
					     (declare (ignorable ,streamvar))
					     (with-slots ,(new-class-all-slots slots superclasses), objectvar
					       ,@(mapcar #'(lambda (x) (slot->read-value x streamvar)) slots))))))

(defmacro define-tagged-binary-class (name (&rest superclasses) slots &rest options)
  (with-gensyms (typevar objectvar streamvar)
    `(define-generic-binary-class ,name ,superclasses ,slots
				  (defmethod read-value ((,typevar (eql ',name)) ,streamvar &key)
				    (let* ,(mapcar #'(lambda (x) (slot-binding x streamvar)) slots)
				      (let ((,objectvar
					     (make-instance
					      ,@(or (cdr (assoc :dispatch options))
						    (error "Must supply :dispatch form."))
					      ,@(mapcan #'slot->keyword-arg slots))))
					(read-object ,objectvar ,streamvar)
					,objectvar))))))

(defun slot-binding (spec stream)
  (destructuring-bind (name (type &rest args)) (normalize-slot-spec spec)
    `(,name (read-value ',type ,stream ,@args))))

(defun slot->keyword-arg (spec)
  (let ((name (first spec)))
    `(,(as-keyword name) ,name)))




; Primitive Binary Types

(defmacro define-binary-type (name (&rest args) &body spec)
  (with-gensyms (type)
    `(progn
       ,(destructuring-bind ((in) &body body) (rest (assoc :reader spec))
			    `(defmethod read-value ((,type (eql ',name)) ,in &key ,@args)
			       ,@body))
       ,(destructuring-bind ((out value) &body body) (rest (assoc :writer spec))
			    `(defmethod write-value ((,type (eql ',name)) ,out ,value &key ,@args)
			       ,@body)))))

(defmacro define-binary-type (name (&rest args) &body spec)
  (ecase (length spec)
    (1
     (with-gensyms (type stream value)
       (destructuring-bind (derived-from &rest derived-args) (mklist (first spec))
	 `(progn
	    (defmethod read-value ((,type (eql ',name)) ,stream &key ,@args)
	      (read-value ',derived-from ,stream ,@derived-args))
	    (defmethod write-value ((,type (eql ',name)) ,stream ,value &key ,@args)
	      (write-value ',derived-from ,stream ,value ,@derived-args))))))
    (2
     (with-gensyms (type)
       `(progn
	  ,(destructuring-bind ((in) &body body) (rest (assoc :reader spec))
			       `(defmethod read-value ((,type (eql ',name)) ,in &key ,@args)
				  ,@body))
	  ,(destructuring-bind ((out value) &body body) (rest (assoc :writer spec))
			       `(defmethod write-value ((,type (eql ',name)) ,out ,value &key ,@args)
				  ,@body)))))))




; The Current Object Stack

(defvar *in-progress-objects* nil)

(defmethod read-object :around (object stream)
  (declare (ignore stream))
  (let ((*in-progress-objects* (cons object *in-progress-objects*)))
    (call-next-method)))

(defmethod write-object :around (object stream)
  (declare (ignore stream))
  (let ((*in-progress-objects* (cons object *in-progress-objects*)))
    (call-next-method)))

(defun current-binary-object () (first *in-progress-objects*))

(defun parent-of-type (type)
  (find-if #'(lambda (x) (typep x type)) *in-progress-objects*))
