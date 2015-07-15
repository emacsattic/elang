;; -*- lexical-binding: t -*-
;;
;;; Tests for compiled lapcode evaluation


(require 'compiler)
(require 'parser)
(require 'tokenizer)

(ert-deftest eval-test-expr ()
  (should (equal (compile-and-run "return")
                 nil))
  (should (equal (compile-and-run "return 1")
                 1))
  (should (equal (compile-and-run "return 2 + 3")
                 5))
  (should (equal (compile-and-run "return 2*(2 + 3)")
                 10)))

(ert-deftest eval-test-equal ()
  (should (equal (compile-and-run "return 1 == 1")
                 t))
  (should (equal (compile-and-run "return 1 != 1")
                 nil)))

(ert-deftest eval-test-or ()
  (should (equal (compile-and-run "return 1 == 1 or 2 == 2")
                 t))
  (should (equal (compile-and-run "return 1 == 2 or 2 == 3")
                 nil)))

(ert-deftest eval-test-and ()
  (should (equal (compile-and-run "return 1 == 1 and 2 == 2")
                 t))
  (should (equal (compile-and-run "return 1 == 1 and 2 == 3")
                 nil)))

(ert-deftest eval-test-assign ()
  (should (equal (compile-and-run "x = 1\nreturn x")
                 1))
  (should (equal (compile-and-run "x = 1\nx = 2\nreturn x")
                 2))
  (should (equal (compile-and-run "x = 1\nx = 2 + x\nreturn x")
                 3))
  (should (equal (compile-and-run "x = 1\nx = x - 1\nreturn x")
                 0))
  (should (equal (compile-and-run "x = 1\ny = 2\nreturn x + y")
                 3)))

(ert-deftest eval-test-while ()
  (should (equal (compile-and-run "a = 10\nwhile a > 1: a = 1\nreturn a")
                 1))
  (should (equal (compile-and-run "a = 10\nwhile a > 1:\n a = 1\n b = 2\nreturn b")
                 2))
  (should (equal (compile-and-run "a = 10\nwhile a > 1: a = a - 1\nreturn a")
                 1)))

(ert-deftest eval-test-if ()
  (should (equal (compile-and-run "a = 1\nif a: a = 2\nreturn a")
                 2))
  (should (equal (compile-and-run "a = 1\nif not a: a = 2\nreturn a")
                 1))
  (should (equal (compile-and-run "a = 1\nif a: a = 2\nelse: a = 3\nreturn a")
                 2))
  (should (equal (compile-and-run "a = 1\nif not a: a = 2\nelse: a = 3\nreturn a")
                 3))
  (should (equal (compile-and-run "a = 1\nif a > 10: a = 2\nelif a < 2: a = 3\nelse: a = 4\nreturn a")
                 3))
  (should (equal (compile-and-run "a = 1\nif a > 10: a = 2\nelif a > 2: a = 3\nelif a > 0: a = 4\nelse: a = 5\nreturn a")
                 4)))

(ert-deftest eval-test-return ()
  (should (equal (compile-and-run "a = 1\nif a > 1: return 2\nreturn 1")
                 1))
  (should (equal (compile-and-run "a = 2\nif a > 1: return a + 1\nreturn 1")
                 3)))

(ert-deftest eval-test-funcall ()
  (fset 'testfun #'(lambda () 1))
  (should (equal (compile-and-run "return testfun()")
                 1))
  (fset 'testfun #'(lambda (arg) arg))
  (should (equal (compile-and-run "return testfun(2)")
                 2))
  (fset 'testfun #'(lambda (arg1 arg2) (+ arg1 arg2)))
  (should (equal (compile-and-run "return testfun(1+2, 2)")
                 5))
  (fset 'testfun nil))
