(defpackage :com.gigamonkeys.macro-utilities
  (:use :common-lisp)
  (:export :with-gensyms
	   :once-only))

(in-package :com.gigamonkeys.macro-utilities)

(defmacro with-gensyms ((&rest names) &body body)
  `(let ,(loop for n in names collect `(,n (gensym)))
     ,@body))

(defmacro once-only ((&rest names) &body body)
  (let ((gensyms (loop for n in names collect (gensym))))
    `(let (,@(loop for g in gensyms collect `(,g (gensym))))
      `(let (,,@(loop for g in gensyms for n in names collect ``(,,g ,,n)))
        ,(let (,@(loop for n in names for g in gensyms collect `(,n ,g)))
           ,@body)))))
