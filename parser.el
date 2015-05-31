;; -*- lexical-binding: t -*-
;;
;; A simple RD parser for a Python-like language. Directly outputs an AST.

(require 'tokenizer)

(eval-when-compile (require 'names))

(define-namespace parser-

;;; Parser
;;; ------

(defvar token-stream
  nil)

(defun parse (tokens)
  (setq token-stream tokens))

(defun parse-atom ()
  (dbind (type value start end line) (car token-stream)
    (cond
     ((current-token-p 'LPAR)
      (pop token-stream)
      (let ((testlist (parse-testlist)))
        (check-pop-current-token 'RPAR)
        testlist))
     ((eq type 'NAME)
      (pop token-stream)
      (intern value))
     ((eq type 'NUMBER)
      (pop token-stream)
      (string-to-number value))
     ((eq type 'STRING)
      (pop token-stream)
      (read value))
     (t (throw 'parser-error (format "Unexpected token: %s" type))))))

(defun parse-power ()
  (let ((atom (parse-atom)))
    (dbind (type value start end line) (car token-stream)
      (cond
       ((current-token-p 'DOUBLESTAR)
        (pop token-stream)
        (list (intern "**") atom (parse-power)))
       (t atom)))))

(defun parse-factor ()
  (dbind (type value start end line) (car token-stream)
    (cond
     ((or (current-token-p 'MINUS)
          (current-token-p 'PLUS))
      (pop token-stream)
      (list (intern value) (parse-factor)))
     (t
      (parse-power)))))

(defun parse-term ()
  (let ((factor (parse-factor)))
    (dbind (type value start end line) (car token-stream)
      (cond
       ((or (current-token-p 'STAR)
            (current-token-p 'SLASH)
            (current-token-p 'PERCENT))
        (pop token-stream)
        (list (intern value) factor (parse-factor)))
       (t
        factor)))))

(defun parse-expr ()
  (let ((term (parse-term)))
    (dbind (type value start end line) (car token-stream)
      (cond
       ((or (current-token-p 'PLUS)
            (current-token-p 'MINUS))
        (pop token-stream)
        (list (intern value) term (parse-term)))
       (t
        term)))))

(defconst comp-ops '(LESS GREATER EQEQUAL GREATEREQUAL LESSEQUAL NOTEQUAL))
(defun parse-comp-op ()
  (when (not (current-token-one-of-p comp-ops))
    (throw 'parser-error (format "Unexpected token: %s" (car token-stream))))
  (dbind (type value start end line) (pop token-stream)
    (intern value)))

(defun parse-comparison ()
  (let ((expr (parse-expr)))
    (while (current-token-one-of-p comp-ops)
      (setq expr (list (parse-comp-op) expr (parse-expr))))
    expr))

(defun parse-not-test ()
  (cond ((current-token-p 'NAME '("not"))
         (pop token-stream)
         (list 'not (parse-not-test)))
        (t (parse-comparison))))

(defun parse-and-test ()
  (let ((not-test (parse-not-test)))
    (while (current-token-p 'NAME '("and"))
      (pop token-stream)
      (setq not-test (list 'and not-test (parse-not-test))))
    not-test))

(defun parse-test ()
  (let ((test (parse-and-test)))
    (while (current-token-p 'NAME '("or"))
      (pop token-stream)
      (setq test (list 'or test (parse-and-test))))
    test))

(defun parse-exprlist ()
  (let ((exprlist (list (parse-expr))))
    (while (current-token-p 'COMMA)
      (pop token-stream)
      (push (parse-expr) exprlist))
    (reverse exprlist)))

(defconst testlist-type-firstset '(STRING NUMBER NAME))
(defconst testlist-val-firstset '("(" "not" "-" "+"))
(defun parse-testlist ()
  (let ((testlist (list (parse-test))))
    (while (current-token-p 'COMMA)
      (pop token-stream)
      (push (parse-test) testlist))
    (if (length1-p testlist)
        (car testlist)
      (reverse testlist))))

(defconst expr-type-firstset '(STRING NUMBER NAME MINUS PLUS RPAR))
(defconst expr-val-firstset '("not"))
(defun parse-expr-stmt ()
  (let ((testlist-left (parse-testlist)))
    (cond ((current-token-p 'EQUAL)
           (pop token-stream)
           (list 'assign testlist-left (parse-testlist)))
          (t testlist-left))))

(defconst flow-val-firstset '("break" "continue" "return"))
(defun parse-flow-stmt ()
  (let* ((current-token (car token-stream))
         (token-value (cadr current-token)))
    (cond
     ((current-token-p 'NAME '("break" "continue"))
      (intern token-value))
     ((current-token-p 'NAME '("return"))
      (parse-return-stmt))
     (t (throw 'parser-error "Unexpected token")))))

(defun parse-return-stmt ()
  (check-pop-current-token 'NAME '("return"))
  'return
  (if (current-token-in-firstset-p testlist-type-firstset
                                   testlist-val-firstset)
      (list 'return (parse-testlist))
    'return))

(defun parse-assert-stmt ()
  (check-pop-current-token 'NAME '("assert"))
  (list 'assert (parse-test)))

(defconst small-type-firstset '(STRING NUMBER NAME MINUS LPAR PLUS))
(defconst small-val-firstset '("return" "assert" "not" "pass" "break" "continue"))
(defun parse-small-stmt ()
  (cond
   ((current-token-in-firstset-p nil
                                 flow-val-firstset)
    (parse-flow-stmt))
   ((current-token-in-firstset-p nil
                                 '("assert"))
    (parse-assert-stmt))
   ((current-token-in-firstset-p nil
                                 '("pass"))
    (pop token-stream)
    nil)
   ((current-token-in-firstset-p expr-type-firstset
                                 expr-val-firstset)
    (parse-expr-stmt))
   (t (throw 'parser-error "Unexpected token"))))

(defconst simple-type-firstset '(STRING NUMBER NAME MINUS LPAR PLUS))
(defconst simple-val-firstset '("return" "assert" "not" "pass" "break" "continue"))
(defun parse-simple-stmt ()
  (let ((small-stmts (list (parse-small-stmt))))
    (when (current-token-p 'SEMI)
      (pop token-stream))
    (while (current-token-in-firstset-p small-type-firstset
                                        small-val-firstset)
      (push (parse-small-stmt) small-stmts)
      (when (current-token-p 'SEMI)
        (pop token-stream)))
    (check-pop-current-token 'NEWLINE)
    (if (length1-p small-stmts)
        (car small-stmts)
      `(progn ,@(reverse small-stmts)))))

(defun parse-suite ()
  (cond
   ((current-token-p 'NEWLINE)
    (pop token-stream)
    (check-pop-current-token 'INDENT)
    (let ((stmtlist (list (parse-simple-stmt))))
      (while (current-token-in-firstset-p stmt-type-firstset
                                          stmt-val-firstset)
        (push (parse-stmt) stmtlist))
      (check-pop-current-token 'DEDENT)
      (if (length1-p stmtlist)
          (car stmtlist)
        `(progn ,@(reverse stmtlist)))))
   (t (parse-simple-stmt))))

(defun parse-while ()
  (check-pop-current-token 'NAME '("while"))
  (let ((test (parse-test))
        suite)
    (check-pop-current-token 'COLON)
    (list 'while test (parse-suite))))

;; TODO: simplify
(defun parse-if ()
  (check-pop-current-token 'NAME '("if"))
  (let ((iftest (parse-test))
        ifsuite
        eliftestsuites
        elsesuite)
    (check-pop-current-token 'COLON)
    (setq ifsuite (parse-suite))
    (while (current-token-p 'NAME '("elif"))
      (pop token-stream)
      (let ((test (parse-test))
            suite)
        (check-pop-current-token 'COLON)
        (setq suite (parse-suite))
        (push (cons test suite) eliftestsuites )))
    (when (current-token-p 'NAME '("else"))
      (pop token-stream)
      (check-pop-current-token 'COLON)
      (setq elsesuite (parse-suite)))
    (list 'cond iftest ifsuite eliftestsuites elsesuite)))

(defun parse-varargslist ()
  (let ((args (list (intern (second (check-pop-current-token 'NAME))))))
    (while (current-token-p 'COMMA)
      (pop token-stream)
      (push (intern (second (check-pop-current-token 'NAME))) args))
    (reverse args)))

(defun parse-parameters ()
  (check-pop-current-token 'LPAR)
  (let (varargslist)
    (when (current-token-p 'NAME)
      (setq varargslist (parse-varargslist)))
    (check-pop-current-token 'RPAR)
    varargslist))

(defun parse-funcdef ()
  (check-pop-current-token 'NAME '("def"))
  (let ((name (second (check-pop-current-token 'NAME)))
        (params (parse-parameters))
        body)
    (check-pop-current-token 'COLON)
    (setq body (parse-suite))
    (list 'defun name params body)))

(defun parse-compound-stmt ()
  (cond
   ((current-token-p 'NAME '("while"))
    (parse-while))
   ((current-token-p 'NAME '("def"))
    (parse-funcdef))
   ((current-token-p 'NAME '("if"))
    (parse-if))
   (t (throw 'parser-error "Unexpected token"))))

(defconst stmt-type-firstset '(STRING NUMBER NAME MINUS LPAR PLUS))
(defconst stmt-val-firstset
  '("return" "assert" "if" "not" "pass" "def" "break" "continue" "while"))
(defun parse-stmt ()
  (cond
   ((current-token-p 'NAME '("while" "def" "if"))
    (parse-compound-stmt))
   ((or (current-token-p 'NAME '("return" "assert" "not" "pass" "break" "continue") )
        (current-token-p 'MINUS)
        (current-token-p 'LPAR)
        (current-token-p 'PLUS)
        (current-token-p 'STRING )
        (current-token-p 'NUMBER)
        (current-token-p 'NAME))
    (parse-simple-stmt))
   (t (throw 'parser-error "Unexpected token"))))

(defun parse-single-input ()
  (cond
   ((current-token-p 'NEWLINE)
    (pop token-stream)
    nil)
   ((current-token-p 'NAME '("while" "def" "if"))
    (parse-compound-stmt))
   ((or (current-token-p 'NAME '("return" "assert" "not" "pass" "break" "continue") )
        (current-token-p 'MINUS)
        (current-token-p 'LPAR)
        (current-token-p 'PLUS)
        (current-token-p 'STRING )
        (current-token-p 'NUMBER)
        (current-token-p 'NAME))
    (parse-simple-stmt))
   (t (throw 'parser-error "Unexpected token"))))

(defun parse-file-input ()
  (let (res)
    (while (not (current-token-p 'ENDMARKER))
      (cond
       ((or (current-token-p 'NEWLINE)
            (current-token-p 'NL))
        (pop token-stream))
       (t
        (push (parse-stmt) res))))
    (check-pop-current-token 'ENDMARKER)
    (reverse res)))

;;; Utils
;;; -----

(defun current-token-p (check-type &optional check-values)
  (dbind (type value start end line) (car token-stream)
    (and (eq type check-type)
         (if check-values
             (member value check-values)
           t))))

(defun current-token-one-of-p (check-types)
  (dbind (type value start end line) (car token-stream)
    (memq type check-types)))

(defun check-pop-current-token (check-type &optional check-values)
  (if (current-token-p check-type check-values)
      (pop token-stream)
    (throw 'parser-error (format "Unexpected token: %s insted of %s"
                                 (caar token-stream) check-type))))

(defun current-token-in-firstset-p (type-set val-set)
  (let* ((token (car token-stream))
         (type (car token))
         (value (cadr token)))
    (when (or (member value val-set)
              (memq type type-set))
      t)))

(defun length1-p (l)
  (= (length l) 1))

(defalias 'dbind 'destructuring-bind)

) ;; end parser- namespace

(provide 'parser)
