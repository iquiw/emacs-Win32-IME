;;; subr-tests.el --- Tests for subr.el

;; Copyright (C) 2015-2016 Free Software Foundation, Inc.

;; Author: Oleh Krehel <ohwoeowho@gmail.com>,
;;         Nicolas Petton <nicolas@petton.fr>
;; Keywords:

;; This file is part of GNU Emacs.

;; GNU Emacs is free software: you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; GNU Emacs is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with GNU Emacs.  If not, see <http://www.gnu.org/licenses/>.

;;; Commentary:

;;

;;; Code:

(require 'ert)

(ert-deftest let-when-compile ()
  ;; good case
  (should (equal (macroexpand '(let-when-compile ((foo (+ 2 3)))
                                (setq bar (eval-when-compile (+ foo foo)))
                                (setq boo (eval-when-compile (* foo foo)))))
                 '(progn
                   (setq bar (quote 10))
                   (setq boo (quote 25)))))
  ;; bad case: `eval-when-compile' omitted, byte compiler should catch this
  (should (equal (macroexpand
                  '(let-when-compile ((foo (+ 2 3)))
                    (setq bar (+ foo foo))
                    (setq boo (eval-when-compile (* foo foo)))))
                 '(progn
                   (setq bar (+ foo foo))
                   (setq boo (quote 25)))))
  ;; something practical
  (should (equal (macroexpand
                  '(let-when-compile ((keywords '("true" "false")))
                    (font-lock-add-keywords
                     'c++-mode
                     `((,(eval-when-compile
                           (format "\\<%s\\>" (regexp-opt keywords)))
                         0 font-lock-keyword-face)))))
                 '(font-lock-add-keywords
                   (quote c++-mode)
                   (list
                    (cons (quote
                           "\\<\\(?:\\(?:fals\\|tru\\)e\\)\\>")
                     (quote
                      (0 font-lock-keyword-face))))))))

(ert-deftest number-sequence-test ()
  (should (= (length
              (number-sequence (1- most-positive-fixnum) most-positive-fixnum))
             2))
  (should (= (length
              (number-sequence
               (1+ most-negative-fixnum) most-negative-fixnum -1))
             2)))

(ert-deftest string-comparison-test ()
  (should (string-lessp "abc" "acb"))
  (should (string-lessp "aBc" "abc"))
  (should (string-lessp "abc" "abcd"))
  (should (string-lessp "abc" "abcd"))
  (should-not (string-lessp "abc" "abc"))
  (should-not (string-lessp "" ""))

  (should (string-greaterp "acb" "abc"))
  (should (string-greaterp "abc" "aBc"))
  (should (string-greaterp "abcd" "abc"))
  (should (string-greaterp "abcd" "abc"))
  (should-not (string-greaterp "abc" "abc"))
  (should-not (string-greaterp "" ""))

  ;; Symbols are also accepted
  (should (string-lessp 'abc 'acb))
  (should (string-lessp "abc" 'acb))
  (should (string-greaterp 'acb 'abc))
  (should (string-greaterp "acb" 'abc)))

(ert-deftest subr-test-when ()
  (should (equal (when t 1) 1))
  (should (equal (when t 2) 2))
  (should (equal (when nil 1) nil))
  (should (equal (when nil 2) nil))
  (should (equal (when t 'x 1) 1))
  (should (equal (when t 'x 2) 2))
  (should (equal (when nil 'x 1) nil))
  (should (equal (when nil 'x 2) nil))
  (let ((x 1))
    (should-not (when nil
                  (setq x (1+ x))
                  x))
    (should (= x 1))
    (should (= 2 (when t
                   (setq x (1+ x))
                   x)))
    (should (= x 2)))
  (should (equal (macroexpand-all '(when a b c d))
                 '(if a (progn b c d)))))

(ert-deftest subr-test-version-parsing ()
  (should (equal (version-to-list ".5") '(0 5)))
  (should (equal (version-to-list "0.9 alpha1") '(0 9 -3 1)))
  (should (equal (version-to-list "0.9 snapshot") '(0  9 -4)))
  (should (equal (version-to-list "0.9-alpha1") '(0 9 -3 1)))
  (should (equal (version-to-list "0.9-snapshot") '(0  9 -4)))
  (should (equal (version-to-list "0.9.snapshot") '(0  9 -4)))
  (should (equal (version-to-list "0.9_snapshot") '(0  9 -4)))
  (should (equal (version-to-list "0.9alpha1") '(0 9 -3 1)))
  (should (equal (version-to-list "0.9snapshot") '(0  9 -4)))
  (should (equal (version-to-list "1.0 git") '(1  0 -4)))
  (should (equal (version-to-list "1.0 pre2") '(1 0 -1 2)))
  (should (equal (version-to-list "1.0-git") '(1  0 -4)))
  (should (equal (version-to-list "1.0-pre2") '(1 0 -1 2)))
  (should (equal (version-to-list "1.0.1-a") '(1 0 1 1)))
  (should (equal (version-to-list "1.0.1-f") '(1 0 1 6)))
  (should (equal (version-to-list "1.0.1.a") '(1 0 1 1)))
  (should (equal (version-to-list "1.0.1.f") '(1 0 1 6)))
  (should (equal (version-to-list "1.0.1_a") '(1 0 1 1)))
  (should (equal (version-to-list "1.0.1_f") '(1 0 1 6)))
  (should (equal (version-to-list "1.0.1a") '(1 0 1 1)))
  (should (equal (version-to-list "1.0.1f") '(1 0 1 6)))
  (should (equal (version-to-list "1.0.7.5") '(1 0 7 5)))
  (should (equal (version-to-list "1.0.git") '(1  0 -4)))
  (should (equal (version-to-list "1.0.pre2") '(1 0 -1 2)))
  (should (equal (version-to-list "1.0_git") '(1  0 -4)))
  (should (equal (version-to-list "1.0_pre2") '(1 0 -1 2)))
  (should (equal (version-to-list "1.0git") '(1  0 -4)))
  (should (equal (version-to-list "1.0pre2") '(1 0 -1 2)))
  (should (equal (version-to-list "22.8 beta3") '(22 8 -2 3)))
  (should (equal (version-to-list "22.8-beta3") '(22 8 -2 3)))
  (should (equal (version-to-list "22.8.beta3") '(22 8 -2 3)))
  (should (equal (version-to-list "22.8_beta3") '(22 8 -2 3)))
  (should (equal (version-to-list "22.8beta3") '(22 8 -2 3)))
  (should (equal (version-to-list "6.9.30 Beta") '(6 9 30 -2)))
  (should (equal (version-to-list "6.9.30-Beta") '(6 9 30 -2)))
  (should (equal (version-to-list "6.9.30.Beta") '(6 9 30 -2)))
  (should (equal (version-to-list "6.9.30Beta") '(6 9 30 -2)))
  (should (equal (version-to-list "6.9.30_Beta") '(6 9 30 -2)))

  (should (equal
            (error-message-string (should-error (version-to-list "OTP-18.1.5")))
            "Invalid version syntax: `OTP-18.1.5' (must start with a number)"))
  (should (equal
            (error-message-string (should-error (version-to-list "")))
            "Invalid version syntax: `' (must start with a number)"))
  (should (equal
            (error-message-string (should-error (version-to-list "1.0..7.5")))
            "Invalid version syntax: `1.0..7.5'"))
  (should (equal
            (error-message-string (should-error (version-to-list "1.0prepre2")))
            "Invalid version syntax: `1.0prepre2'"))
  (should (equal
            (error-message-string (should-error (version-to-list "22.8X3")))
            "Invalid version syntax: `22.8X3'"))
  (should (equal
            (error-message-string (should-error (version-to-list "beta22.8alpha3")))
            "Invalid version syntax: `beta22.8alpha3' (must start with a number)"))
  (should (equal
            (error-message-string (should-error (version-to-list "honk")))
            "Invalid version syntax: `honk' (must start with a number)"))
  (should (equal
            (error-message-string (should-error (version-to-list 9)))
            "Version must be a string"))

  (let ((version-separator "_"))
    (should (equal (version-to-list "_5") '(0 5)))
    (should (equal (version-to-list "0_9 alpha1") '(0 9 -3 1)))
    (should (equal (version-to-list "0_9 snapshot") '(0  9 -4)))
    (should (equal (version-to-list "0_9-alpha1") '(0 9 -3 1)))
    (should (equal (version-to-list "0_9-snapshot") '(0  9 -4)))
    (should (equal (version-to-list "0_9.alpha1") '(0 9 -3 1)))
    (should (equal (version-to-list "0_9.snapshot") '(0  9 -4)))
    (should (equal (version-to-list "0_9alpha1") '(0 9 -3 1)))
    (should (equal (version-to-list "0_9snapshot") '(0  9 -4)))
    (should (equal (version-to-list "1_0 git") '(1  0 -4)))
    (should (equal (version-to-list "1_0 pre2") '(1 0 -1 2)))
    (should (equal (version-to-list "1_0-git") '(1  0 -4)))
    (should (equal (version-to-list "1_0.pre2") '(1 0 -1 2)))
    (should (equal (version-to-list "1_0_1-a") '(1 0 1 1)))
    (should (equal (version-to-list "1_0_1-f") '(1 0 1 6)))
    (should (equal (version-to-list "1_0_1.a") '(1 0 1 1)))
    (should (equal (version-to-list "1_0_1.f") '(1 0 1 6)))
    (should (equal (version-to-list "1_0_1_a") '(1 0 1 1)))
    (should (equal (version-to-list "1_0_1_f") '(1 0 1 6)))
    (should (equal (version-to-list "1_0_1a") '(1 0 1 1)))
    (should (equal (version-to-list "1_0_1f") '(1 0 1 6)))
    (should (equal (version-to-list "1_0_7_5") '(1 0 7 5)))
    (should (equal (version-to-list "1_0_git") '(1  0 -4)))
    (should (equal (version-to-list "1_0pre2") '(1 0 -1 2)))
    (should (equal (version-to-list "22_8 beta3") '(22 8 -2 3)))
    (should (equal (version-to-list "22_8-beta3") '(22 8 -2 3)))
    (should (equal (version-to-list "22_8.beta3") '(22 8 -2 3)))
    (should (equal (version-to-list "22_8beta3") '(22 8 -2 3)))
    (should (equal (version-to-list "6_9_30 Beta") '(6 9 30 -2)))
    (should (equal (version-to-list "6_9_30-Beta") '(6 9 30 -2)))
    (should (equal (version-to-list "6_9_30.Beta") '(6 9 30 -2)))
    (should (equal (version-to-list "6_9_30Beta") '(6 9 30 -2)))

    (should (equal
              (error-message-string (should-error (version-to-list "1_0__7_5")))
              "Invalid version syntax: `1_0__7_5'"))
    (should (equal
              (error-message-string (should-error (version-to-list "1_0prepre2")))
              "Invalid version syntax: `1_0prepre2'"))
    (should (equal
              (error-message-string (should-error (version-to-list "22.8X3")))
              "Invalid version syntax: `22.8X3'"))
    (should (equal
              (error-message-string (should-error (version-to-list "beta22_8alpha3")))
              "Invalid version syntax: `beta22_8alpha3' (must start with a number)"))))

(provide 'subr-tests)
;;; subr-tests.el ends here
