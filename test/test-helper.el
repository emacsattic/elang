;; -*- lexical-binding: t -*-
;;
;;; Test utility macros and functions

(require 'tokenizer)
(require 'parser)

(defmacro with-tokenized (str &rest body)
  (declare (indent 1))
  `(with-temp-buffer
     (insert ,str)
     (let* ((tokens (reverse (tokenizer-tokenize-region))))
       (setq-local parser-token-stream tokens)
       ,@body)))

(defmacro with-parsed (str &rest body)
  (declare (indent 1))
  `(let (parse-tree)
     (with-tokenized ,str
       (setq parse-tree (parser-parse-single-input)))
     ,@body))

(defmacro with-compiled-single (str &rest body)
  (declare (indent 1))
  `(let (parse-tree)
     (with-tokenized ,str
       (setq parse-tree (parser-parse-single-input)))
     (dbind (codes constants depth) (compiler-compile-to-lapcode parse-tree)
       ,@body)))

(defmacro with-compiled-file (str &rest body)
  (declare (indent 1))
  `(let (parse-tree)
     (with-tokenized ,str
       (setq parse-tree (parser-parse-file-input)))
     (dbind (codes constants depth) (compiler-compile-to-lapcode parse-tree t)
       ,@body)))

(defun compile-to-function (bodystr arglist)
  (with-tokenized bodystr
    (let ((parse-tree (parser-parse-file-input)))
      (dbind (lapcode constants depth) (compiler-compile-to-lapcode parse-tree)
        (make-byte-code
         arglist
         (byte-compile-lapcode lapcode)
         constants
         depth)))))

(defun compile-and-run (bodystr &optional arglist args)
  (let ((fun (compile-to-function bodystr arglist)))
    (if (not arglist) (funcall fun)
      (funcall fun args))))
