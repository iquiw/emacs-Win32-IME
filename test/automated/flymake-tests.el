;;; flymake-tests.el --- Test suite for flymake

;; Copyright (C) 2011-2015 Free Software Foundation, Inc.

;; Author: Eduard Wiebe <usenet@pusto.de>

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

;;; Code:
(require 'ert)
(require 'flymake)

(defvar flymake-tests-data-directory
  (expand-file-name "flymake/warnpred" (getenv "EMACS_TEST_DIRECTORY"))
  "Directory containing flymake test data.")


;; Warning predicate
(defun flymake-tests--current-face (file predicate)
  (let ((buffer (find-file-noselect
                 (expand-file-name file flymake-tests-data-directory))))
    (unwind-protect
        (with-current-buffer buffer
          (setq-local flymake-warning-predicate predicate)
          (goto-char (point-min))
          (flymake-mode 1)
          ;; XXX: is this reliable enough?
          (sleep-for (+ 0.5 flymake-no-changes-timeout))
          (flymake-goto-next-error)
          (face-at-point))
      (and buffer (kill-buffer buffer)))))

(ert-deftest warning-predicate-rx-gcc ()
  "Test GCC warning via regexp predicate."
  (skip-unless (executable-find "gcc"))
  (should (eq 'flymake-warnline
              (flymake-tests--current-face "test.c" "^[Ww]arning"))))

(ert-deftest warning-predicate-function-gcc ()
  "Test GCC warning via function predicate."
  (skip-unless (and (executable-find "gcc") (executable-find "make")))
  (should (eq 'flymake-warnline
              (flymake-tests--current-face "test.c"
               (lambda (msg) (string-match "^[Ww]arning" msg))))))

(ert-deftest warning-predicate-rx-perl ()
  "Test perl warning via regular expression predicate."
  (skip-unless (executable-find "perl"))
  (should (eq 'flymake-warnline
              (flymake-tests--current-face "test.pl" "^Scalar value"))))

(ert-deftest warning-predicate-function-perl ()
  "Test perl warning via function predicate."
  (skip-unless (executable-find "perl"))
  (should (eq 'flymake-warnline
              (flymake-tests--current-face
               "test.pl"
               (lambda (msg) (string-match "^Scalar value" msg))))))

(provide 'flymake-tests)

;;; flymake.el ends here
