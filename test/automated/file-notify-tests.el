;;; file-notify-tests.el --- Tests of file notifications  -*- lexical-binding: t; -*-

;; Copyright (C) 2013-2016 Free Software Foundation, Inc.

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

;;; Commentary:

;; Some of the tests require access to a remote host files.  Since
;; this could be problematic, a mock-up connection method "mock" is
;; used.  Emulating a remote connection, it simply calls "sh -i".
;; Tramp's file name handlers still run, so this test is sufficient
;; except for connection establishing.

;; If you want to test a real Tramp connection, set
;; $REMOTE_TEMPORARY_FILE_DIRECTORY to a suitable value in order to
;; overwrite the default value.  If you want to skip tests accessing a
;; remote host, set this environment variable to "/dev/null" or
;; whatever is appropriate on your system.

;; A whole test run can be performed calling the command `file-notify-test-all'.

;;; Code:

(require 'ert)
(require 'filenotify)
(require 'tramp)

;; There is no default value on w32 systems, which could work out of the box.
(defconst file-notify-test-remote-temporary-file-directory
  (cond
   ((getenv "REMOTE_TEMPORARY_FILE_DIRECTORY"))
   ((eq system-type 'windows-nt) null-device)
   (t (add-to-list
       'tramp-methods
       '("mock"
	 (tramp-login-program        "sh")
	 (tramp-login-args           (("-i")))
	 (tramp-remote-shell         "/bin/sh")
	 (tramp-remote-shell-args    ("-c"))
	 (tramp-connection-timeout   10)))
      (format "/mock::%s" temporary-file-directory)))
  "Temporary directory for Tramp tests.")

(defvar file-notify--test-tmpfile nil)
(defvar file-notify--test-tmpfile1 nil)
(defvar file-notify--test-desc nil)
(defvar file-notify--test-desc1 nil)
(defvar file-notify--test-desc2 nil)
(defvar file-notify--test-results nil)
(defvar file-notify--test-event nil)
(defvar file-notify--test-events nil)

(defconst file-notify--test-read-event-timeout 0.01
  "Timeout for `read-event' calls.
It is different for local and remote file notification libraries.")

(defun file-notify--test-timeout ()
  "Timeout to wait for arriving events, in seconds."
  (cond
   ((file-remote-p temporary-file-directory) 6)
   ((string-equal (file-notify--test-library) "w32notify") 4)
   ((eq system-type 'cygwin) 10)
   (t 3)))

(defun file-notify--test-cleanup ()
  "Cleanup after a test."
  (file-notify-rm-watch file-notify--test-desc)
  (file-notify-rm-watch file-notify--test-desc1)
  (file-notify-rm-watch file-notify--test-desc2)

  (ignore-errors
    (delete-file (file-newest-backup file-notify--test-tmpfile)))
  (ignore-errors
    (if (file-directory-p file-notify--test-tmpfile)
        (delete-directory file-notify--test-tmpfile 'recursive)
      (delete-file file-notify--test-tmpfile)))
  (ignore-errors
    (if (file-directory-p file-notify--test-tmpfile1)
        (delete-directory file-notify--test-tmpfile1 'recursive)
      (delete-file file-notify--test-tmpfile1)))
  (ignore-errors
    (when (file-remote-p temporary-file-directory)
      (tramp-cleanup-connection
       (tramp-dissect-file-name temporary-file-directory) nil 'keep-password)))

  (setq file-notify--test-tmpfile nil
        file-notify--test-tmpfile1 nil
        file-notify--test-desc nil
        file-notify--test-desc1 nil
        file-notify--test-desc2 nil
        file-notify--test-results nil
        file-notify--test-events nil)
  (when file-notify--test-event
    (error "file-notify--test-event should not be set but bound dynamically")))

(setq password-cache-expiry nil
      tramp-verbose 0
      tramp-message-show-message nil)

;; This shall happen on hydra only.
(when (getenv "NIX_STORE")
  (add-to-list 'tramp-remote-path 'tramp-own-remote-path))

;; We do not want to try and fail `file-notify-add-watch'.
(defun file-notify--test-local-enabled ()
  "Whether local file notification is enabled.
This is needed for local `temporary-file-directory' only, in the
remote case we return always t."
  (or file-notify--library
      (file-remote-p temporary-file-directory)))

(defvar file-notify--test-remote-enabled-checked nil
  "Cached result of `file-notify--test-remote-enabled'.
If the function did run, the value is a cons cell, the `cdr'
being the result.")

(defun file-notify--test-remote-enabled ()
  "Whether remote file notification is enabled."
  (unless (consp file-notify--test-remote-enabled-checked)
    (let (desc)
      (ignore-errors
        (and
         (file-remote-p file-notify-test-remote-temporary-file-directory)
         (file-directory-p file-notify-test-remote-temporary-file-directory)
         (file-writable-p file-notify-test-remote-temporary-file-directory)
         (setq desc
               (file-notify-add-watch
                file-notify-test-remote-temporary-file-directory
                '(change) 'ignore))))
      (setq file-notify--test-remote-enabled-checked (cons t desc))
      (when desc (file-notify-rm-watch desc))))
  ;; Return result.
  (cdr file-notify--test-remote-enabled-checked))

(defun file-notify--test-library ()
  "The used library for the test, as a string.
In the remote case, it is the process name which runs on the
remote host, or nil."
  (if (null (file-remote-p temporary-file-directory))
      (symbol-name file-notify--library)
    (and (consp file-notify--test-remote-enabled-checked)
	 (processp (cdr file-notify--test-remote-enabled-checked))
	 (replace-regexp-in-string
	  "<[[:digit:]]+>\\'" ""
	  (process-name (cdr file-notify--test-remote-enabled-checked))))))

(defmacro file-notify--deftest-remote (test docstring)
  "Define ert `TEST-remote' for remote files."
  (declare (indent 1))
  `(ert-deftest ,(intern (concat (symbol-name test) "-remote")) ()
     ,docstring
     :tags '(:expensive-test)
     (let* ((temporary-file-directory
	     file-notify-test-remote-temporary-file-directory)
            (file-notify--test-read-event-timeout 0.1)
	    (ert-test (ert-get-test ',test)))
       (skip-unless (file-notify--test-remote-enabled))
       (tramp-cleanup-connection
	(tramp-dissect-file-name temporary-file-directory) nil 'keep-password)
       (funcall (ert-test-body ert-test)))))

(ert-deftest file-notify-test00-availability ()
  "Test availability of `file-notify'."
  (skip-unless (file-notify--test-local-enabled))
  ;; Report the native library which has been used.
  (message "Library: `%s'" (file-notify--test-library))
  (should
   (setq file-notify--test-desc
         (file-notify-add-watch temporary-file-directory '(change) 'ignore)))

  ;; Cleanup.
  (file-notify--test-cleanup))

(file-notify--deftest-remote file-notify-test00-availability
  "Test availability of `file-notify' for remote files.")

(ert-deftest file-notify-test01-add-watch ()
  "Check `file-notify-add-watch'."
  (skip-unless (file-notify--test-local-enabled))

  (setq file-notify--test-tmpfile  (file-notify--test-make-temp-name)
        file-notify--test-tmpfile1
        (format "%s/%s" file-notify--test-tmpfile (md5 (current-time-string))))

  ;; Check, that different valid parameters are accepted.
  (should
   (setq file-notify--test-desc
         (file-notify-add-watch temporary-file-directory '(change) 'ignore)))
  (file-notify-rm-watch file-notify--test-desc)
  (should
   (setq file-notify--test-desc
         (file-notify-add-watch
          temporary-file-directory '(attribute-change) 'ignore)))
  (file-notify-rm-watch file-notify--test-desc)
  (should
   (setq file-notify--test-desc
         (file-notify-add-watch
          temporary-file-directory '(change attribute-change) 'ignore)))
  (file-notify-rm-watch file-notify--test-desc)
  (write-region "any text" nil file-notify--test-tmpfile nil 'no-message)
  (should
   (setq file-notify--test-desc
         (file-notify-add-watch
          file-notify--test-tmpfile '(change attribute-change) 'ignore)))
  (file-notify-rm-watch file-notify--test-desc)
  (delete-file file-notify--test-tmpfile)

  ;; Check error handling.
  (should-error (file-notify-add-watch 1 2 3 4)
                :type 'wrong-number-of-arguments)
  (should
   (equal (should-error
           (file-notify-add-watch 1 2 3))
          '(wrong-type-argument 1)))
  (should
   (equal (should-error
           (file-notify-add-watch temporary-file-directory 2 3))
          '(wrong-type-argument 2)))
  (should
   (equal (should-error
           (file-notify-add-watch temporary-file-directory '(change) 3))
          '(wrong-type-argument 3)))
  ;; The upper directory of a file must exist.
  (should
   (equal (should-error
           (file-notify-add-watch
            file-notify--test-tmpfile1 '(change attribute-change) 'ignore))
          `(file-notify-error
            "Directory does not exist" ,file-notify--test-tmpfile)))

  ;; Cleanup.
  (file-notify--test-cleanup))

(file-notify--deftest-remote file-notify-test01-add-watch
  "Check `file-notify-add-watch' for remote files.")

(defun file-notify--test-event-test ()
  "Ert test function to be called by `file-notify--test-event-handler'.
We cannot pass arguments, so we assume that `file-notify--test-event'
is bound somewhere."
  ;; Check the descriptor.
  (should (equal (car file-notify--test-event) file-notify--test-desc))
  ;; Check the file name.
  (should
   (string-prefix-p
    (file-notify--event-watched-file file-notify--test-event)
    (file-notify--event-file-name file-notify--test-event)))
  ;; Check the second file name if exists.
  (when (eq (nth 1 file-notify--test-event) 'renamed)
    (should
     (string-prefix-p
      (file-notify--event-watched-file file-notify--test-event)
      (file-notify--event-file1-name file-notify--test-event)))))

(defun file-notify--test-event-handler (event)
  "Run a test over FILE-NOTIFY--TEST-EVENT.
For later analysis, append the test result to `file-notify--test-results'
and the event to `file-notify--test-events'."
  (let* ((file-notify--test-event event)
         (result
          (ert-run-test (make-ert-test :body 'file-notify--test-event-test))))
    ;; Do not add lock files, this would confuse the checks.
    (unless (string-match
	     (regexp-quote ".#")
	     (file-notify--event-file-name file-notify--test-event))
      ;;(message "file-notify--test-event-handler result: %s event: %S"
               ;;(null (ert-test-failed-p result)) file-notify--test-event)
      (setq file-notify--test-events
	    (append file-notify--test-events `(,file-notify--test-event))
	    file-notify--test-results
	    (append file-notify--test-results `(,result))))))

(defun file-notify--test-make-temp-name ()
  "Create a temporary file name for test."
  (expand-file-name
   (make-temp-name "file-notify-test") temporary-file-directory))

(defmacro file-notify--wait-for-events (timeout until)
  "Wait for and return file notification events until form UNTIL is true.
TIMEOUT is the maximum time to wait for, in seconds."
  `(with-timeout (,timeout (ignore))
     (while (null ,until)
       (read-event nil nil file-notify--test-read-event-timeout))))

(defun file-notify--test-with-events-check (events)
  "Check whether received events match one of the EVENTS alternatives."
  (let (result)
    (dolist (elt events result)
      (setq result
            (or result
                (equal elt (mapcar #'cadr file-notify--test-events)))))))

(defun file-notify--test-with-events-explainer (events)
  "Explain why `file-notify--test-with-events-check' fails."
  (if (null (cdr events))
      (format "Received events `%s' do not match expected events `%s'"
              (mapcar #'cadr file-notify--test-events) (car events))
    (format
     "Received events `%s' do not match any sequence of expected events `%s'"
     (mapcar #'cadr file-notify--test-events) events)))

(put 'file-notify--test-with-events-check 'ert-explainer
     'file-notify--test-with-events-explainer)

(defmacro file-notify--test-with-events (events &rest body)
  "Run BODY collecting events and then compare with EVENTS.
EVENTS is either a simple list of events, or a list of lists of
events, which represent different possible results.  Don't wait
longer than timeout seconds for the events to be delivered."
  (declare (indent 1))
  `(let* ((events (if (consp (car ,events)) ,events (list ,events)))
          (max-length (apply 'max (mapcar 'length events)))
          create-lockfiles)
     ;; Flush pending events.
     (file-notify--wait-for-events
      (file-notify--test-timeout)
      (input-pending-p))
     (setq file-notify--test-events nil
           file-notify--test-results nil)
     ,@body
     (file-notify--wait-for-events
      ;; More events need more time.  Use some fudge factor.
      (* (ceiling max-length 100) (file-notify--test-timeout))
      (= max-length (length file-notify--test-events)))
     ;; Check the result sequence just to make sure that all events
     ;; are as expected.
     (dolist (result file-notify--test-results)
       (when (ert-test-failed-p result)
         (ert-fail
          (cadr (ert-test-result-with-condition-condition result)))))
     ;; One of the possible event sequences shall match.
     (should (file-notify--test-with-events-check events))))

(ert-deftest file-notify-test02-events ()
  "Check file creation/change/removal notifications."
  (skip-unless (file-notify--test-local-enabled))

  (unwind-protect
      (progn
        ;; Check file creation, change and deletion.  It doesn't work
        ;; for cygwin and kqueue, because we don't use an implicit
        ;; directory monitor (kqueue), or the timings are too bad (cygwin).
        (unless (or (eq system-type 'cygwin)
		    (string-equal (file-notify--test-library) "kqueue"))
          (setq file-notify--test-tmpfile (file-notify--test-make-temp-name))
          (should
           (setq file-notify--test-desc
                 (file-notify-add-watch
                  file-notify--test-tmpfile
                  '(change) 'file-notify--test-event-handler)))
          (file-notify--test-with-events
              (cond
               ;; cygwin recognizes only `deleted' and `stopped' events.
               ((eq system-type 'cygwin)
                '(deleted stopped))
               (t '(created changed deleted stopped)))
            (write-region
             "another text" nil file-notify--test-tmpfile nil 'no-message)
            (read-event nil nil file-notify--test-read-event-timeout)
            (delete-file file-notify--test-tmpfile))
          (file-notify-rm-watch file-notify--test-desc))

        ;; Check file change and deletion.
	(setq file-notify--test-tmpfile (file-notify--test-make-temp-name))
        (write-region "any text" nil file-notify--test-tmpfile nil 'no-message)
	(should
	 (setq file-notify--test-desc
	       (file-notify-add-watch
		file-notify--test-tmpfile
		'(change) 'file-notify--test-event-handler)))
        (file-notify--test-with-events
	    (cond
	     ;; cygwin recognizes only `deleted' and `stopped' events.
	     ((eq system-type 'cygwin)
	      '(deleted stopped))
             ;; inotify and kqueue raise just one `changed' event.
             ((or (string-equal "inotify" (file-notify--test-library))
                  (string-equal "kqueue" (file-notify--test-library)))
	      '(changed deleted stopped))
             ;; gfilenotify raises one or two `changed' events
             ;; randomly, no chance to test.  So we accept both cases.
             ((string-equal "gfilenotify" (file-notify--test-library))
              '((changed deleted stopped)
                (changed changed deleted stopped)))
	     (t '(changed changed deleted stopped)))
          (read-event nil nil file-notify--test-read-event-timeout)
          (write-region
           "another text" nil file-notify--test-tmpfile nil 'no-message)
          (read-event nil nil file-notify--test-read-event-timeout)
          (delete-file file-notify--test-tmpfile))
        (file-notify-rm-watch file-notify--test-desc)

        ;; Check file creation, change and deletion when watching a
        ;; directory.  There must be a `stopped' event when deleting
        ;; the directory.
	(let ((temporary-file-directory
	       (make-temp-file "file-notify-test-parent" t)))
	  (should
	   (setq file-notify--test-tmpfile (file-notify--test-make-temp-name)
		 file-notify--test-desc
		 (file-notify-add-watch
		  temporary-file-directory
		  '(change) 'file-notify--test-event-handler)))
	  (file-notify--test-with-events
	      (cond
	       ;; w32notify does not raise `deleted' and `stopped'
	       ;; events for the watched directory.
	       ((string-equal (file-notify--test-library) "w32notify")
		'(created changed deleted))
	       ;; cygwin recognizes only `deleted' and `stopped' events.
	       ((eq system-type 'cygwin)
		'(deleted stopped))
	       ;; There are two `deleted' events, for the file and for
	       ;; the directory.  Except for kqueue.
	       ((string-equal (file-notify--test-library) "kqueue")
		'(created changed deleted stopped))
	       (t '(created changed deleted deleted stopped)))
	    (read-event nil nil file-notify--test-read-event-timeout)
	    (write-region
	     "any text" nil file-notify--test-tmpfile nil 'no-message)
	    (read-event nil nil file-notify--test-read-event-timeout)
	    (delete-directory temporary-file-directory 'recursive))
          (file-notify-rm-watch file-notify--test-desc))

        ;; Check copy of files inside a directory.
	(let ((temporary-file-directory
	       (make-temp-file "file-notify-test-parent" t)))
	  (should
	   (setq file-notify--test-tmpfile (file-notify--test-make-temp-name)
		 file-notify--test-tmpfile1 (file-notify--test-make-temp-name)
		 file-notify--test-desc
		 (file-notify-add-watch
		  temporary-file-directory
		  '(change) 'file-notify--test-event-handler)))
	  (file-notify--test-with-events
	      (cond
	       ;; w32notify does not distinguish between `changed' and
	       ;; `attribute-changed'.  It does not raise `deleted'
	       ;; and `stopped' events for the watched directory.
	       ((string-equal (file-notify--test-library) "w32notify")
		'(created changed created changed
		  changed changed changed
		  deleted deleted))
	       ;; cygwin recognizes only `deleted' and `stopped' events.
	       ((eq system-type 'cygwin)
		'(deleted stopped))
	       ;; There are three `deleted' events, for two files and
	       ;; for the directory.  Except for kqueue.
	       ((string-equal (file-notify--test-library) "kqueue")
		'(created changed created changed deleted stopped))
	       (t '(created changed created changed
		    deleted deleted deleted stopped)))
	    (read-event nil nil file-notify--test-read-event-timeout)
	    (write-region
	     "any text" nil file-notify--test-tmpfile nil 'no-message)
	    (read-event nil nil file-notify--test-read-event-timeout)
	    (copy-file file-notify--test-tmpfile file-notify--test-tmpfile1)
	    ;; The next two events shall not be visible.
	    (read-event nil nil file-notify--test-read-event-timeout)
	    (set-file-modes file-notify--test-tmpfile 000)
	    (read-event nil nil file-notify--test-read-event-timeout)
	    (set-file-times file-notify--test-tmpfile '(0 0))
	    (read-event nil nil file-notify--test-read-event-timeout)
	    (delete-directory temporary-file-directory 'recursive))
          (file-notify-rm-watch file-notify--test-desc))

        ;; Check rename of files inside a directory.
	(let ((temporary-file-directory
	       (make-temp-file "file-notify-test-parent" t)))
	  (should
	   (setq file-notify--test-tmpfile (file-notify--test-make-temp-name)
		 file-notify--test-tmpfile1 (file-notify--test-make-temp-name)
		 file-notify--test-desc
		 (file-notify-add-watch
		  temporary-file-directory
		  '(change) 'file-notify--test-event-handler)))
	  (file-notify--test-with-events
	      (cond
	       ;; w32notify does not raise `deleted' and `stopped'
	       ;; events for the watched directory.
	       ((string-equal (file-notify--test-library) "w32notify")
		'(created changed renamed deleted))
	       ;; cygwin recognizes only `deleted' and `stopped' events.
	       ((eq system-type 'cygwin)
		'(deleted stopped))
	       ;; There are two `deleted' events, for the file and for
	       ;; the directory.  Except for kqueue.
	       ((string-equal (file-notify--test-library) "kqueue")
		'(created changed renamed deleted stopped))
	       (t '(created changed renamed deleted deleted stopped)))
	    (read-event nil nil file-notify--test-read-event-timeout)
	    (write-region
	     "any text" nil file-notify--test-tmpfile nil 'no-message)
	    (read-event nil nil file-notify--test-read-event-timeout)
	    (rename-file file-notify--test-tmpfile file-notify--test-tmpfile1)
	    ;; After the rename, we won't get events anymore.
	    (read-event nil nil file-notify--test-read-event-timeout)
	    (delete-directory temporary-file-directory 'recursive))
          (file-notify-rm-watch file-notify--test-desc))

        ;; Check attribute change.  Does not work for cygwin.
	(unless (eq system-type 'cygwin)
	  (setq file-notify--test-tmpfile (file-notify--test-make-temp-name))
	  (write-region
	   "any text" nil file-notify--test-tmpfile nil 'no-message)
	  (should
	   (setq file-notify--test-desc
		 (file-notify-add-watch
		  file-notify--test-tmpfile
		  '(attribute-change) 'file-notify--test-event-handler)))
	  (file-notify--test-with-events
	      (cond
	       ;; w32notify does not distinguish between `changed' and
	       ;; `attribute-changed'.
	       ((string-equal (file-notify--test-library) "w32notify")
		'(changed changed changed changed))
	       ;; For kqueue and in the remote case, `write-region'
	       ;; raises also an `attribute-changed' event.
	       ((or (string-equal (file-notify--test-library) "kqueue")
		    (file-remote-p temporary-file-directory))
		'(attribute-changed attribute-changed attribute-changed))
	       (t '(attribute-changed attribute-changed)))
	    (read-event nil nil file-notify--test-read-event-timeout)
	    (write-region
	     "any text" nil file-notify--test-tmpfile nil 'no-message)
	    (read-event nil nil file-notify--test-read-event-timeout)
	    (set-file-modes file-notify--test-tmpfile 000)
	    (read-event nil nil file-notify--test-read-event-timeout)
	    (set-file-times file-notify--test-tmpfile '(0 0))
	    (read-event nil nil file-notify--test-read-event-timeout)
	    (delete-file file-notify--test-tmpfile))
          (file-notify-rm-watch file-notify--test-desc)))

    ;; Cleanup.
    (file-notify--test-cleanup)))

(file-notify--deftest-remote file-notify-test02-events
  "Check file creation/change/removal notifications for remote files.")

(require 'autorevert)
(setq auto-revert-notify-exclude-dir-regexp "nothing-to-be-excluded"
      auto-revert-remote-files t
      auto-revert-stop-on-user-input nil)

(ert-deftest file-notify-test03-autorevert ()
  "Check autorevert via file notification."
  (skip-unless (file-notify--test-local-enabled))
  ;; `auto-revert-buffers' runs every 5".  And we must wait, until the
  ;; file has been reverted.
  (let ((timeout (if (file-remote-p temporary-file-directory) 60 10))
        buf)
    (unwind-protect
	(progn
	  (setq file-notify--test-tmpfile (file-notify--test-make-temp-name))

	  (write-region
	   "any text" nil file-notify--test-tmpfile nil 'no-message)
	  (setq buf (find-file-noselect file-notify--test-tmpfile))
	  (with-current-buffer buf
	    (should (string-equal (buffer-string) "any text"))
            ;; `buffer-stale--default-function' checks for
            ;; `verify-visited-file-modtime'.  We must ensure that it
            ;; returns nil.
            (sleep-for 1)
	    (auto-revert-mode 1)

	    ;; `auto-revert-buffers' runs every 5".
	    (with-timeout (timeout (ignore))
	      (while (null auto-revert-notify-watch-descriptor)
		(sleep-for 1)))

	    ;; Check, that file notification has been used.
	    (should auto-revert-mode)
	    (should auto-revert-use-notify)
	    (should auto-revert-notify-watch-descriptor)

	    ;; Modify file.  We wait for a second, in order to have
	    ;; another timestamp.
            (with-current-buffer (get-buffer-create "*Messages*")
              (narrow-to-region (point-max) (point-max)))
	    (sleep-for 1)
            (write-region
             "another text" nil file-notify--test-tmpfile nil 'no-message)

	    ;; Check, that the buffer has been reverted.
	    (with-current-buffer (get-buffer-create "*Messages*")
	      (file-notify--wait-for-events
	       timeout
	       (string-match
                (format-message "Reverting buffer `%s'." (buffer-name buf))
                (buffer-string))))
	    (should (string-match "another text" (buffer-string)))

            ;; Stop file notification.  Autorevert shall still work via polling.
	    (file-notify-rm-watch auto-revert-notify-watch-descriptor)
	    (file-notify--wait-for-events
	     timeout (null auto-revert-use-notify))
	    (should-not auto-revert-use-notify)
	    (should-not auto-revert-notify-watch-descriptor)

	    ;; Modify file.  We wait for two seconds, in order to
	    ;; have another timestamp.  One second seems to be too
	    ;; short.
	    (with-current-buffer (get-buffer-create "*Messages*")
	      (narrow-to-region (point-max) (point-max)))
	    (sleep-for 2)
	    (write-region
	     "foo bla" nil file-notify--test-tmpfile nil 'no-message)

	    ;; Check, that the buffer has been reverted.
	    (with-current-buffer (get-buffer-create "*Messages*")
	      (file-notify--wait-for-events
	       timeout
	       (string-match
		(format-message "Reverting buffer `%s'." (buffer-name buf))
		(buffer-string))))
	    (should (string-match "foo bla" (buffer-string)))))

      ;; Cleanup.
      (with-current-buffer "*Messages*" (widen))
      (ignore-errors (kill-buffer buf))
      (file-notify--test-cleanup))))

(file-notify--deftest-remote file-notify-test03-autorevert
  "Check autorevert via file notification for remote files.")

(ert-deftest file-notify-test04-file-validity ()
  "Check `file-notify-valid-p' for files."
  (skip-unless (file-notify--test-local-enabled))

  (unwind-protect
      (progn
        (setq file-notify--test-tmpfile (file-notify--test-make-temp-name))
	(write-region "any text" nil file-notify--test-tmpfile nil 'no-message)
	(should
	 (setq file-notify--test-desc
	       (file-notify-add-watch
		file-notify--test-tmpfile
		'(change) #'file-notify--test-event-handler)))
        (should (file-notify-valid-p file-notify--test-desc))
	;; After calling `file-notify-rm-watch', the descriptor is not
	;; valid anymore.
        (file-notify-rm-watch file-notify--test-desc)
        (should-not (file-notify-valid-p file-notify--test-desc))
	(delete-file file-notify--test-tmpfile))

    ;; Cleanup.
    (file-notify--test-cleanup))

  (unwind-protect
      (progn
        (setq file-notify--test-tmpfile (file-notify--test-make-temp-name))
	(write-region "any text" nil file-notify--test-tmpfile nil 'no-message)
	(should
	 (setq file-notify--test-desc
	       (file-notify-add-watch
		file-notify--test-tmpfile
		'(change) #'file-notify--test-event-handler)))
        (file-notify--test-with-events
            (cond
             ;; cygwin recognizes only `deleted' and `stopped' events.
	     ((eq system-type 'cygwin)
	      '(deleted stopped))
             ;; inotify and kqueue raise just one `changed' event.
             ((or (string-equal "inotify" (file-notify--test-library))
                  (string-equal "kqueue" (file-notify--test-library)))
	      '(changed deleted stopped))
             ;; gfilenotify raises one or two `changed' events
             ;; randomly, no chance to test.  So we accept both cases.
             ((string-equal "gfilenotify" (file-notify--test-library))
              '((changed deleted stopped)
                (changed changed deleted stopped)))
	     (t '(changed changed deleted stopped)))
          (should (file-notify-valid-p file-notify--test-desc))
	  (read-event nil nil file-notify--test-read-event-timeout)
          (write-region
           "another text" nil file-notify--test-tmpfile nil 'no-message)
	  (read-event nil nil file-notify--test-read-event-timeout)
	  (delete-file file-notify--test-tmpfile))
	;; After deleting the file, the descriptor is not valid anymore.
        (should-not (file-notify-valid-p file-notify--test-desc))
        (file-notify-rm-watch file-notify--test-desc))

    ;; Cleanup.
    (file-notify--test-cleanup))

  (unwind-protect
      (let ((temporary-file-directory
	     (make-temp-file "file-notify-test-parent" t)))
	(should
	 (setq file-notify--test-tmpfile (file-notify--test-make-temp-name)
	       file-notify--test-desc
	       (file-notify-add-watch
		temporary-file-directory
		'(change) #'file-notify--test-event-handler)))
	(file-notify--test-with-events
	 (cond
	  ;; w32notify does not raise `deleted' and `stopped' events
	  ;; for the watched directory.
	  ((string-equal (file-notify--test-library) "w32notify")
	   '(created changed deleted))
	  ;; cygwin recognizes only `deleted' and `stopped' events.
	  ((eq system-type 'cygwin)
	   '(deleted stopped))
	  ;; There are two `deleted' events, for the file and for the
	  ;; directory.  Except for kqueue.
	  ((string-equal (file-notify--test-library) "kqueue")
	   '(created changed deleted stopped))
	  (t '(created changed deleted deleted stopped)))
	 (should (file-notify-valid-p file-notify--test-desc))
	 (read-event nil nil file-notify--test-read-event-timeout)
	 (write-region
	  "any text" nil file-notify--test-tmpfile nil 'no-message)
	 (read-event nil nil file-notify--test-read-event-timeout)
	 (delete-directory temporary-file-directory t))
	;; After deleting the parent directory, the descriptor must
	;; not be valid anymore.
	(should-not (file-notify-valid-p file-notify--test-desc)))

    ;; Cleanup.
    (file-notify--test-cleanup)))

(file-notify--deftest-remote file-notify-test04-file-validity
  "Check `file-notify-valid-p' via file notification for remote files.")

(ert-deftest file-notify-test05-dir-validity ()
  "Check `file-notify-valid-p' for directories."
  (skip-unless (file-notify--test-local-enabled))

  (unwind-protect
      (progn
        (setq file-notify--test-tmpfile
	      (file-name-as-directory (file-notify--test-make-temp-name)))
        (make-directory file-notify--test-tmpfile)
	(should
	 (setq file-notify--test-desc
	       (file-notify-add-watch
		file-notify--test-tmpfile
		'(change) #'file-notify--test-event-handler)))
        (should (file-notify-valid-p file-notify--test-desc))
        ;; After removing the watch, the descriptor must not be valid
        ;; anymore.
        (file-notify-rm-watch file-notify--test-desc)
        (file-notify--wait-for-events
         (file-notify--test-timeout)
	 (not (file-notify-valid-p file-notify--test-desc)))
        (should-not (file-notify-valid-p file-notify--test-desc)))

    ;; Cleanup.
    (file-notify--test-cleanup))

  (unwind-protect
      (progn
	(setq file-notify--test-tmpfile
	      (file-name-as-directory (file-notify--test-make-temp-name)))
        (make-directory file-notify--test-tmpfile)
	(should
	 (setq file-notify--test-desc
	       (file-notify-add-watch
		file-notify--test-tmpfile
		'(change) #'file-notify--test-event-handler)))
        (should (file-notify-valid-p file-notify--test-desc))
        ;; After deleting the directory, the descriptor must not be
        ;; valid anymore.
        (delete-directory file-notify--test-tmpfile t)
        (file-notify--wait-for-events
	 (file-notify--test-timeout)
	 (not (file-notify-valid-p file-notify--test-desc)))
        (should-not (file-notify-valid-p file-notify--test-desc)))

    ;; Cleanup.
    (file-notify--test-cleanup)))

(file-notify--deftest-remote file-notify-test05-dir-validity
  "Check `file-notify-valid-p' via file notification for remote directories.")

(ert-deftest file-notify-test06-many-events ()
  "Check that events are not dropped."
  :tags '(:expensive-test)
  (skip-unless (file-notify--test-local-enabled))
  ;; Under cygwin events arrive in random order.  Impossible to define a test.
  (skip-unless (not (eq system-type 'cygwin)))

  (setq file-notify--test-tmpfile (file-notify--test-make-temp-name))
  (make-directory file-notify--test-tmpfile)
  (should
   (setq file-notify--test-desc
	 (file-notify-add-watch
	  file-notify--test-tmpfile
	  '(change) 'file-notify--test-event-handler)))
  (unwind-protect
      (let ((n 1000)
            source-file-list target-file-list
            (default-directory file-notify--test-tmpfile))
        (dotimes (i n)
	  ;; It matters which direction we rename, at least for
	  ;; kqueue.  This backend parses directories in alphabetic
	  ;; order (x%d before y%d).  So we rename into both directions.
	  (if (zerop (mod i 2))
	      (progn
		(push (expand-file-name (format "x%d" i)) source-file-list)
		(push (expand-file-name (format "y%d" i)) target-file-list))
	    (push (expand-file-name (format "y%d" i)) source-file-list)
	    (push (expand-file-name (format "x%d" i)) target-file-list)))
        (file-notify--test-with-events (make-list (+ n n) 'created)
          (let ((source-file-list source-file-list)
                (target-file-list target-file-list))
            (while (and source-file-list target-file-list)
              (read-event nil nil file-notify--test-read-event-timeout)
              (write-region "" nil (pop source-file-list) nil 'no-message)
              (read-event nil nil file-notify--test-read-event-timeout)
              (write-region "" nil (pop target-file-list) nil 'no-message))))
        (file-notify--test-with-events
	    (cond
	     ;; w32notify fires both `deleted' and `renamed' events.
	     ((string-equal (file-notify--test-library) "w32notify")
	      (let (r)
		(dotimes (_i n r)
		  (setq r (append '(deleted renamed) r)))))
	     (t (make-list n 'renamed)))
          (let ((source-file-list source-file-list)
                (target-file-list target-file-list))
            (while (and source-file-list target-file-list)
              (read-event nil nil file-notify--test-read-event-timeout)
              (rename-file (pop source-file-list) (pop target-file-list) t))))
        (file-notify--test-with-events (make-list n 'deleted)
          (dolist (file target-file-list)
            (read-event nil nil file-notify--test-read-event-timeout)
            (delete-file file) file-notify--test-read-event-timeout)))

    ;; Cleanup.
    (file-notify--test-cleanup)))

(file-notify--deftest-remote file-notify-test06-many-events
   "Check that events are not dropped for remote directories.")

(ert-deftest file-notify-test07-backup ()
  "Check that backup keeps file notification."
  (skip-unless (file-notify--test-local-enabled))

  (unwind-protect
      (progn
        (setq file-notify--test-tmpfile (file-notify--test-make-temp-name))
	(write-region "any text" nil file-notify--test-tmpfile nil 'no-message)
	(should
	 (setq file-notify--test-desc
	       (file-notify-add-watch
		file-notify--test-tmpfile
		'(change) #'file-notify--test-event-handler)))
        (should (file-notify-valid-p file-notify--test-desc))
        (file-notify--test-with-events
	    (cond
             ;; For w32notify and in the remote case, there are two
             ;; `changed' events.
             ((or (string-equal (file-notify--test-library) "w32notify")
                  (file-remote-p temporary-file-directory))
              '(changed changed))
             ;; gfilenotify raises one or two `changed' events
             ;; randomly, no chance to test.  So we accept both cases.
             ((string-equal "gfilenotify" (file-notify--test-library))
              '((changed)
                (changed changed)))
             (t '(changed)))
          ;; There shouldn't be any problem, because the file is kept.
          (with-temp-buffer
            (let ((buffer-file-name file-notify--test-tmpfile)
                  (make-backup-files t)
                  (backup-by-copying t)
                  (kept-new-versions 1)
                  (delete-old-versions t))
              (insert "another text")
              (save-buffer))))
        ;; After saving the buffer, the descriptor is still valid.
        (should (file-notify-valid-p file-notify--test-desc))
	(delete-file file-notify--test-tmpfile))

    ;; Cleanup.
    (file-notify--test-cleanup))

  (unwind-protect
      (progn
        ;; It doesn't work for kqueue, because we don't use an
        ;; implicit directory monitor.
        (unless (string-equal (file-notify--test-library) "kqueue")
	  (setq file-notify--test-tmpfile (file-notify--test-make-temp-name))
	  (write-region
	   "any text" nil file-notify--test-tmpfile nil 'no-message)
	  (should
	   (setq file-notify--test-desc
		 (file-notify-add-watch
		  file-notify--test-tmpfile
		  '(change) #'file-notify--test-event-handler)))
	  (should (file-notify-valid-p file-notify--test-desc))
	  (file-notify--test-with-events '(renamed created changed)
	    ;; The file is renamed when creating a backup.  It shall
	    ;; still be watched.
	    (with-temp-buffer
	      (let ((buffer-file-name file-notify--test-tmpfile)
		    (make-backup-files t)
		    (backup-by-copying nil)
		    (backup-by-copying-when-mismatch nil)
		    (kept-new-versions 1)
		    (delete-old-versions t))
		(insert "another text")
		(save-buffer))))
	  ;; After saving the buffer, the descriptor is still valid.
	  (should (file-notify-valid-p file-notify--test-desc))
	  (delete-file file-notify--test-tmpfile)))

    ;; Cleanup.
    (file-notify--test-cleanup)))

(file-notify--deftest-remote file-notify-test07-backup
  "Check that backup keeps file notification for remote files.")

(ert-deftest file-notify-test08-watched-file-in-watched-dir ()
  "Watches a directory and a file in that directory separately.
Checks that the callbacks are only called with events with
descriptors that were issued when registering the watches.  This
test caters for the situation in bug#22736 where the callback for
the directory received events for the file with the descriptor of
the file watch."
  :tags '(:expensive-test)
  (skip-unless (file-notify--test-local-enabled))

  ;; A directory to be watched.
  (should
   (setq file-notify--test-tmpfile
         (make-temp-file "file-notify-test-parent" t)))
  ;; A file to be watched.
  (should
   (setq file-notify--test-tmpfile1
         (let ((temporary-file-directory file-notify--test-tmpfile))
           (file-notify--test-make-temp-name))))
  (write-region "any text" nil file-notify--test-tmpfile1 nil 'no-message)
  (unwind-protect
      (cl-flet (;; Directory monitor.
                (dir-callback (event)
                 (let ((file-notify--test-desc file-notify--test-desc1))
                   (file-notify--test-event-handler event)))
                ;; File monitor.
                (file-callback (event)
                 (let ((file-notify--test-desc file-notify--test-desc2))
                   (file-notify--test-event-handler event))))
        (should
         (setq file-notify--test-desc1
               (file-notify-add-watch
                file-notify--test-tmpfile
                '(change) #'dir-callback)))
        (should
         (setq file-notify--test-desc2
               (file-notify-add-watch
                file-notify--test-tmpfile1
                '(change) #'file-callback)))
        (should (file-notify-valid-p file-notify--test-desc1))
        (should (file-notify-valid-p file-notify--test-desc2))
        (should-not (equal file-notify--test-desc1 file-notify--test-desc2))
        ;; gfilenotify raises one or two `changed' events randomly in
        ;; the file monitor, no chance to test.
        (unless (string-equal "gfilenotify" (file-notify--test-library))
          (let ((n 100) events)
            ;; Compute the expected events.
            (dotimes (_i (/ n 2))
              (setq events
                    (append
                     (append
                      ;; Directory monitor and file monitor.
                      (cond
                       ;; In the remote case, there are two `changed'
                       ;; events.
		       ((file-remote-p temporary-file-directory)
                        '(changed changed changed changed))
                       ;; The directory monitor in kqueue does not
                       ;; raise any `changed' event.  Just the file
                       ;; monitor event is received.
                       ((string-equal (file-notify--test-library) "kqueue")
                        '(changed))
                       ;; Otherwise, both monitors report the
                       ;; `changed' event.
                       (t '(changed changed)))
                      ;; Just the directory monitor.
                      (cond
                       ;; In kqueue, there is an additional `changed'
                       ;; event.  Why?
                       ((string-equal (file-notify--test-library) "kqueue")
                        '(changed created changed))
                       (t '(created changed))))
                     events)))

            ;; Run the test.
            (file-notify--test-with-events events
              (dotimes (i n)
                (read-event nil nil file-notify--test-read-event-timeout)
                (if (zerop (mod i 2))
                    (write-region
                     "any text" nil file-notify--test-tmpfile1 t 'no-message)
                  (let ((temporary-file-directory file-notify--test-tmpfile))
                    (write-region
                     "any text" nil
                     (file-notify--test-make-temp-name) nil 'no-message)))))))

        ;; If we delete the file, the directory monitor shall still be
        ;; active.  We receive the `deleted' event from both the
        ;; directory and the file monitor.  The `stopped' event is
        ;; from the file monitor.  It's undecided in which order the
        ;; the directory and the file monitor are triggered.
        (file-notify--test-with-events
            '((deleted deleted stopped)
              (deleted stopped deleted))
          (delete-file file-notify--test-tmpfile1))
        (should (file-notify-valid-p file-notify--test-desc1))
        (should-not (file-notify-valid-p file-notify--test-desc2))

        ;; Now we delete the directory.
        (file-notify--test-with-events
            (cond
             ;; In kqueue, just one `deleted' event for the directory
             ;; is received.
             ((string-equal (file-notify--test-library) "kqueue")
              '(deleted stopped))
             (t (append
                 ;; The directory monitor raises a `deleted' event for
                 ;; every file contained in the directory, we must
                 ;; count them.
                 (make-list
                  (length
                   (directory-files
                    file-notify--test-tmpfile nil
                    directory-files-no-dot-files-regexp 'nosort))
                  'deleted)
                 ;; The events of the directory itself.
                 (cond
		  ;; w32notify does not raise `deleted' and `stopped'
		  ;; events for the watched directory.
                  ((string-equal (file-notify--test-library) "w32notify") '())
                  (t '(deleted stopped))))))
          (delete-directory file-notify--test-tmpfile 'recursive))
        (should-not (file-notify-valid-p file-notify--test-desc1))
        (should-not (file-notify-valid-p file-notify--test-desc2)))

    ;; Cleanup.
    (file-notify--test-cleanup)))

(file-notify--deftest-remote file-notify-test08-watched-file-in-watched-dir
  "Check `file-notify-test08-watched-file-in-watched-dir' for remote files.")

(defun file-notify-test-all (&optional interactive)
  "Run all tests for \\[file-notify]."
  (interactive "p")
  (if interactive
      (ert-run-tests-interactively "^file-notify-")
    (ert-run-tests-batch "^file-notify-")))

;; TODO:

;; * kqueue does not send all expected `deleted' events.  Maybe due to
;;   the missing directory monitor.
;; * For w32notify, no `deleted' and `stopped' events arrive when a
;;   directory is removed.
;; * For w32notify, no `attribute-changed' events arrive.  Its sends
;;   `changed' events instead.
;; * Check, why cygwin recognizes only `deleted' and `stopped' events.

(provide 'file-notify-tests)
;;; file-notify-tests.el ends here
