;;; thingatpt.el --- tests for thing-at-point.

;; Copyright (C) 2013-2017 Free Software Foundation, Inc.

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

;;; Code:

(require 'ert)

(defvar thing-at-point-test-data
  '(("http://1.gnu.org" 1  url "http://1.gnu.org")
    ("http://2.gnu.org" 6 url "http://2.gnu.org")
    ("http://3.gnu.org" 19 url "http://3.gnu.org")
    ("https://4.gnu.org" 1  url "https://4.gnu.org")
    ("A geo URI (geo:3.14159,-2.71828)." 12 url "geo:3.14159,-2.71828")
    ("Visit http://5.gnu.org now." 5 url nil)
    ("Visit http://6.gnu.org now." 7 url "http://6.gnu.org")
    ("Visit http://7.gnu.org now." 22 url "http://7.gnu.org")
    ("Visit http://8.gnu.org now." 22 url "http://8.gnu.org")
    ("Visit http://9.gnu.org now." 24 url nil)
    ;; Invalid URIs
    ("<<<<" 2 url nil)
    ("<>" 1 url nil)
    ("<url:>" 1 url nil)
    ("http://" 1 url nil)
    ;; Invalid schema
    ("foo://www.gnu.org" 1 url nil)
    ("foohttp://www.gnu.org" 1 url nil)
    ;; Non alphanumeric characters can be found in URIs
    ("ftp://example.net/~foo!;#bar=baz&goo=bob" 3 url "ftp://example.net/~foo!;#bar=baz&goo=bob")
    ("bzr+ssh://user@example.net:5/a%20d,5" 34 url "bzr+ssh://user@example.net:5/a%20d,5")
    ;; <url:...> markup
    ("Url: <url:foo://1.example.com>..." 8 url "foo://1.example.com")
    ("Url: <url:foo://2.example.com>..." 30 url "foo://2.example.com")
    ("Url: <url:foo://www.gnu.org/a bc>..." 20 url "foo://www.gnu.org/a bc")
    ;; Hack used by thing-at-point: drop punctuation at end of URI.
    ("Go to http://www.gnu.org, for details" 7 url "http://www.gnu.org")
    ("Go to http://www.gnu.org." 24 url "http://www.gnu.org")
    ;; Standard URI delimiters
    ("Go to \"http://10.gnu.org\"." 8 url "http://10.gnu.org")
    ("Go to \"http://11.gnu.org/\"." 26 url "http://11.gnu.org/")
    ("Go to <http://12.gnu.org> now." 8 url "http://12.gnu.org")
    ("Go to <http://13.gnu.org> now." 24 url "http://13.gnu.org")
    ;; Parenthesis handling (non-standard)
    ("http://example.com/a(b)c" 21 url "http://example.com/a(b)c")
    ("http://example.com/a(b)" 21 url "http://example.com/a(b)")
    ("(http://example.com/abc)" 2 url "http://example.com/abc")
    ("This (http://example.com/a(b))" 7 url "http://example.com/a(b)")
    ("This (http://example.com/a(b))" 30 url "http://example.com/a(b)")
    ("This (http://example.com/a(b))" 5 url nil)
    ("http://example.com/ab)c" 4 url "http://example.com/ab)c")
    ;; URL markup, lacking schema
    ("<url:foo@example.com>" 1 url "mailto:foo@example.com")
    ("<url:ftp.example.net/abc/>" 1 url "ftp://ftp.example.net/abc/"))
  "List of thing-at-point tests.
Each list element should have the form

  (STRING POS THING RESULT)

where STRING is a string of buffer contents, POS is the value of
point, THING is a symbol argument for `thing-at-point', and
RESULT should be the result of calling `thing-at-point' from that
position to retrieve THING.")

(ert-deftest thing-at-point-tests ()
  "Test the file-local variables implementation."
  (dolist (test thing-at-point-test-data)
    (with-temp-buffer
      (insert (nth 0 test))
      (goto-char (nth 1 test))
      (should (equal (thing-at-point (nth 2 test)) (nth 3 test))))))

;;; thingatpt.el ends here
