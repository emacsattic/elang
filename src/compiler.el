;; -*- lexical-binding: t -*-
;;
;;; IR to lapcode compiler

(eval-when-compile (require 'names))

(require 'parser)

(define-namespace compiler-

(defun compile-to-lapcode (parse-tree &optional file-input)
  (let (codes                           ; codes emitted
        constants                       ; constants vector
        (pc 0)                          ; program counter
        (tag-counter 0)                 ; current tag number
        binds                           ; bound var alist
        (depth 0)                       ; current stack depth
        (maxdepth 0)                    ; max stack depth
        )
    (cl-labels
        ( ;; Save a lapcode
         (emit-code (code &optional arg)
                    (push `(,code . ,arg) codes)
                    (setq depth (+ depth (byte-compile-stack-adjustment code arg)))
                    (setq maxdepth (max depth maxdepth)))
         (emit-tag (tag)
                   (push tag codes))
         (make-tag ()
                   (list 'TAG (setq tag-counter (1+ tag-counter))))
         ;; Push a constant into the constants vector
         (add-constant (constant)
                       (push constant constants))
         (add-bind (bindname constidx)
                   (push (cons bindname constidx) binds))
         (unbind-all ()
                     (when binds
                       (emit-code 'byte-unbind (length binds))))
         ;; Compile an expression (main compilation entry point)
         (compile-expr (tree)
                       (cond
                        ((symbolp tree)
                         (emit-code 'byte-varref (length constants))
                         (add-constant tree))
                        ((numberp tree)
                         (emit-code 'byte-constant (length constants))
                         (add-constant tree))
                        ((listp tree)
                         (cl-case (first tree)
                           ('if (compile-if tree))
                           ('assign (compile-assign tree))
                           ('progn (compile-progn tree))
                           ('while (compile-while tree))
                           ('return (compile-return tree))
                           (t (compile-funcall tree))))
                        (t (error "Cannot compile") )))
         ;; Compile a usual function call
         (compile-funcall (tree)
                          (emit-code 'byte-constant (length constants))
                          (add-constant (first tree))
                          (mapc #'compile-expr (rest tree))
                          (emit-code 'byte-call (1- (length tree))))
         ;; Compile the if/then form
         (compile-if (tree)
                     (let ((testexpr (second tree))
                           (thenexpr (third tree))
                           (elseexpr (fourth tree))
                           lapcode)
                       (setq lapcode (if (not elseexpr)
                                         'byte-goto-if-nil-else-pop
                                       'byte-goto-if-nil))
                       (compile-expr testexpr)
                       ;; correct target pc can only be set after compiling
                       ;; thenexpr and elseexpr
                       (let ((after-then-tag (make-tag))
                             (after-else-tag (make-tag)))
                         (emit-code lapcode after-then-tag)
                         (compile-expr thenexpr)
                         (emit-tag after-then-tag)
                         (when elseexpr
                           (emit-code 'byte-goto after-else-tag))
                         (when elseexpr
                           (compile-expr elseexpr))
                         (emit-tag after-else-tag))))
         ;; Compile a list of exprs
         (compile-progn (tree)
                        (let ((forms (rest tree)))
                          (while forms
                            (compile-expr (pop forms))
                            ;; TODO: dirty, move into compile expr as exprs
                            ;; know, whether it is needed
                            (unless (memq (caar codes) '(byte-return
                                                         byte-varbind
                                                         byte-varset))
                              (emit-code 'byte-discard)))))
         ;; Compile an assignment
         (compile-assign (tree)
                         (let ((lvalue (second tree))
                               (rvalue (third tree)))
                           (compile-expr rvalue)
                           (let ((bind (assq lvalue binds))
                                 (constidx (length constants)))
                             (cond ((not bind)
                                    (add-constant lvalue)
                                    (emit-code 'byte-varbind constidx)
                                    (add-bind lvalue constidx))
                                   (t
                                    (emit-code 'byte-varset (cdr bind)))))))
         ;; Compile a while loop
         (compile-while (tree)
                        (let ((testexpr (second tree))
                              (bodyexpr (third tree)))
                          ;; correct
                          (let ((before-while-tag (make-tag))
                                (after-loop-tag (make-tag)))
                            (emit-tag before-while-tag)
                            (compile-expr testexpr)
                            (emit-code 'byte-goto-if-nil-else-pop after-loop-tag)
                            (compile-expr bodyexpr)
                            (emit-code 'byte-discard)
                            (emit-code 'byte-goto before-while-tag)
                            (emit-tag after-loop-tag))))
         ;; Compile a return statement
         (compile-return (tree)
                         (let ((retexpr (second tree)))
                           (if retexpr
                               (compile-expr retexpr)
                             (add-constant nil)
                             (emit-code 'byte-constant (1- (length constants))))
                           (unbind-all)
                           (emit-code 'byte-return))))
      (compile-expr parse-tree)
      ;; Check if the return is implicit (i.e., when the final bytecode is not a return).
      ;; This only works for file-input
      (when (and file-input
                 (not (eq (caar codes) 'byte-return)))
        (add-constant nil)
        (emit-code 'byte-constant (1- (length constants)))
        (unbind-all)
        (emit-code 'byte-return))
      (values (reverse codes) (vconcat (reverse constants)) maxdepth))))

) ;;; end of compiler- namespace

(provide 'compiler)
