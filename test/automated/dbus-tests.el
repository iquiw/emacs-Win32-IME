;;; dbus-tests.el --- Tests of D-Bus integration into Emacs

;; Copyright (C) 2013-2015 Free Software Foundation, Inc.

;; Author: Michael Albinus <michael.albinus@gmx.de>

;; This program is free software: you can redistribute it and/or
;; modify it under the terms of the GNU General Public License as
;; published by the Free Software Foundation, either version 3 of the
;; License, or (at your option) any later version.
;;
;; This program is distributed in the hope that it will be useful, but
;; WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
;; General Public License for more details.
;;
;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see `http://www.gnu.org/licenses/'.

;;; Code:

(require 'ert)
(require 'dbus)

(setq dbus-debug nil)

(defvar dbus--test-enabled-session-bus
  (and (featurep 'dbusbind)
       (dbus-ignore-errors (dbus-get-unique-name :session)))
  "Check, whether we are registered at the session bus.")

(defvar dbus--test-enabled-system-bus
  (and (featurep 'dbusbind)
       (dbus-ignore-errors (dbus-get-unique-name :system)))
  "Check, whether we are registered at the system bus.")

(defun dbus--test-availability (bus)
  "Test availability of D-Bus BUS."
  (should (dbus-list-names bus))
  (should (dbus-list-activatable-names bus))
  (should (dbus-list-known-names bus))
  (should (dbus-get-unique-name bus)))

(ert-deftest dbus-test00-availability-session ()
  "Test availability of D-Bus `:session'."
  :expected-result (if dbus--test-enabled-session-bus :passed :failed)
  (dbus--test-availability :session))

(ert-deftest dbus-test00-availability-system ()
  "Test availability of D-Bus `:system'."
  :expected-result (if dbus--test-enabled-system-bus :passed :failed)
  (dbus--test-availability :system))

(ert-deftest dbus-test01-type-conversion ()
  "Check type conversion functions."
  (let ((ustr "0123abc_xyz\x01\xff")
	(mstr "Grüß Göttin"))
    (should
     (string-equal
      (dbus-byte-array-to-string (dbus-string-to-byte-array "")) ""))
    (should
     (string-equal
      (dbus-byte-array-to-string (dbus-string-to-byte-array ustr)) ustr))
    (should
     (string-equal
      (dbus-byte-array-to-string (dbus-string-to-byte-array mstr) 'multibyte)
      mstr))
    ;; Should not work for multibyte strings.
    (should-not
     (string-equal
      (dbus-byte-array-to-string (dbus-string-to-byte-array mstr)) mstr))

    (should
     (string-equal
      (dbus-unescape-from-identifier (dbus-escape-as-identifier "")) ""))
    (should
     (string-equal
      (dbus-unescape-from-identifier (dbus-escape-as-identifier ustr)) ustr))
    ;; Should not work for multibyte strings.
    (should-not
     (string-equal
      (dbus-unescape-from-identifier (dbus-escape-as-identifier mstr)) mstr))))

(defun dbus--test-register-service (bus)
  "Check service registration at BUS."
  ;; Cleanup.
  (dbus-ignore-errors (dbus-unregister-service bus dbus-service-emacs))

  ;; Register an own service.
  (should (eq (dbus-register-service bus dbus-service-emacs) :primary-owner))
  (should (member dbus-service-emacs (dbus-list-known-names bus)))
  (should (eq (dbus-register-service bus dbus-service-emacs) :already-owner))
  (should (member dbus-service-emacs (dbus-list-known-names bus)))

  ;; Unregister the service.
  (should (eq (dbus-unregister-service bus dbus-service-emacs) :released))
  (should-not (member dbus-service-emacs (dbus-list-known-names bus)))
  (should (eq (dbus-unregister-service bus dbus-service-emacs) :non-existent))
  (should-not (member dbus-service-emacs (dbus-list-known-names bus)))

  ;; `dbus-service-dbus' is reserved for the BUS itself.
  (should-error (dbus-register-service bus dbus-service-dbus))
  (should-error (dbus-unregister-service bus dbus-service-dbus)))

(ert-deftest dbus-test02-register-service-session ()
  "Check service registration at `:session'."
  (skip-unless (and dbus--test-enabled-session-bus
		    (dbus-register-service :session dbus-service-emacs)))
  (dbus--test-register-service :session)

  (let ((service "org.freedesktop.Notifications"))
    (when (member service (dbus-list-known-names :session))
      ;; Cleanup.
      (dbus-ignore-errors (dbus-unregister-service :session service))

      (should (eq (dbus-register-service :session service) :in-queue))
      (should (eq (dbus-unregister-service :session service) :released))

      (should
       (eq (dbus-register-service :session service :do-not-queue) :exists))
      (should (eq (dbus-unregister-service :session service) :not-owner)))))

(ert-deftest dbus-test02-register-service-system ()
  "Check service registration at `:system'."
  (skip-unless (and dbus--test-enabled-system-bus
		    (dbus-register-service :system dbus-service-emacs)))
  (dbus--test-register-service :system))

(defun dbus-test-all (&optional interactive)
  "Run all tests for \\[dbus]."
  (interactive "p")
  (funcall
   (if interactive 'ert-run-tests-interactively 'ert-run-tests-batch) "^dbus"))

(provide 'dbus-tests)
;;; dbus-tests.el ends here
