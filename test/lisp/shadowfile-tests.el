;;; shadowfile-tests.el --- Tests of shadowfile

;; Copyright (C) 2018 Free Software Foundation, Inc.

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

;; A whole test run can be performed calling the command `shadowfile-test-all'.

;;; Code:

(require 'ert)
(require 'shadowfile)
(require 'tramp)

;; There is no default value on w32 systems, which could work out of the box.
(defconst shadow-test-remote-temporary-file-directory
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
      (add-to-list
       'tramp-default-host-alist
       `("\\`mock\\'" nil ,(system-name)))
      ;; Emacs' Makefile sets $HOME to a nonexistent value.  Needed in
      ;; batch mode only, therefore.  It cannot be
      ;; `temporary-directory', because the tests with "~" would fail.
      (unless (and (null noninteractive) (file-directory-p "~/"))
        (setenv "HOME" invocation-directory))
      (format "/mock::%s" temporary-file-directory)))
  "Temporary directory for Tramp tests.")

(defconst shadow-test-info-file
  (expand-file-name "shadows_test" temporary-file-directory)
  "File to keep shadow information in during tests.")

(defconst shadow-test-todo-file
  (expand-file-name "shadow_todo_test" temporary-file-directory)
  "File to store the list of uncopied shadows in during tests.")

(ert-deftest shadow-test00-clusters ()
  "Check cluster definitions.
Per definition, all files are identical on the different hosts of
a cluster (or site).  This is not tested here; it must be
guaranteed by the originator of a cluster definition."
  (skip-unless (file-remote-p shadow-test-remote-temporary-file-directory))

  (let ((text-quoting-style 'grave) ;; We inspect the *Messages* buffer!
        (inhibit-message t)
        (shadow-info-file shadow-test-info-file)
	(shadow-todo-file shadow-test-todo-file)
	shadow-clusters
	cluster primary regexp mocked-input)
    (unwind-protect
	;; We must mock `read-from-minibuffer' and `read-string', in
	;; order to avoid interactive arguments.
	(cl-letf* (((symbol-function 'read-from-minibuffer)
		    (lambda (&rest args) (pop mocked-input)))
		   ((symbol-function 'read-string)
		    (lambda (&rest args) (pop mocked-input))))

	  ;; Cleanup.
	  (when (file-exists-p shadow-info-file)
	    (delete-file shadow-info-file))
	  (when (file-exists-p shadow-todo-file)
	    (delete-file shadow-todo-file))

	  ;; Define a cluster.
	  (setq cluster "cluster"
		primary shadow-system-name
		regexp (shadow-regexp-superquote primary)
		mocked-input `(,cluster ,primary ,regexp))
	  (call-interactively 'shadow-define-cluster)
	  (should
	   (string-equal
	    (shadow-cluster-name (shadow-get-cluster cluster)) cluster))
	  (should
	   (string-equal
	    (shadow-cluster-primary (shadow-get-cluster cluster)) primary))
	  (should
	   (string-equal
	    (shadow-cluster-regexp (shadow-get-cluster cluster)) regexp))
          (should-not (shadow-get-cluster "non-existent-cluster-name"))

          ;; Test `shadow-set-cluster' and `make-shadow-cluster'.
	  (shadow-set-cluster cluster primary regexp)
	  (should
	   (equal (shadow-get-cluster cluster)
		  (make-shadow-cluster
		   :name cluster :primary primary :regexp regexp)))

	  ;; The primary must be either `shadow-system-name', or a remote file.
	  (setq ;; The second "cluster" is wrong.
		mocked-input `(,cluster ,cluster ,primary ,regexp))
          (with-current-buffer (messages-buffer)
            (narrow-to-region (point-max) (point-max)))
	  (call-interactively 'shadow-define-cluster)
	  (should
           (string-match
            (regexp-quote "Not a valid primary!")
            (with-current-buffer (messages-buffer) (buffer-string))))
	  ;; The first cluster definition is still valid.
	  (should
	   (string-equal
	    (shadow-cluster-name (shadow-get-cluster cluster)) cluster))
	  (should
	   (string-equal
	    (shadow-cluster-primary (shadow-get-cluster cluster)) primary))
	  (should
	   (string-equal
	    (shadow-cluster-regexp (shadow-get-cluster cluster)) regexp))

	  ;; The regexp must match the primary name.
	  (setq ;; The second "cluster" is wrong.
		mocked-input `(,cluster ,primary ,cluster ,regexp))
          (with-current-buffer (messages-buffer)
            (narrow-to-region (point-max) (point-max)))
	  (call-interactively 'shadow-define-cluster)
	  (should
           (string-match
            (regexp-quote "Regexp doesn't include the primary host!")
            (with-current-buffer (messages-buffer) (buffer-string))))
	  ;; The first cluster definition is still valid.
	  (should
	   (string-equal
	    (shadow-cluster-name (shadow-get-cluster cluster)) cluster))
	  (should
	   (string-equal
	    (shadow-cluster-primary (shadow-get-cluster cluster)) primary))
	  (should
	   (string-equal
	    (shadow-cluster-regexp (shadow-get-cluster cluster)) regexp))

	  ;; Redefine the cluster.
	  (setq primary
		(file-remote-p shadow-test-remote-temporary-file-directory)
		regexp (shadow-regexp-superquote primary)
		mocked-input `(,cluster ,primary ,regexp))
	  (call-interactively 'shadow-define-cluster)
	  (should
	   (string-equal
	    (shadow-cluster-name (shadow-get-cluster cluster)) cluster))
	  (should
	   (string-equal
	    (shadow-cluster-primary (shadow-get-cluster cluster)) primary))
	  (should
	   (string-equal
	    (shadow-cluster-regexp (shadow-get-cluster cluster)) regexp))

          ;; Test `shadow-set-cluster' and `make-shadow-cluster'.
	  (shadow-set-cluster cluster primary regexp)
	  (should
	   (equal (shadow-get-cluster cluster)
		  (make-shadow-cluster
		   :name cluster :primary primary :regexp regexp))))

      ;; Cleanup.
      (with-current-buffer (messages-buffer) (widen))
      (when (file-exists-p shadow-info-file)
	(delete-file shadow-info-file))
      (when (file-exists-p shadow-todo-file)
	(delete-file shadow-todo-file)))))

(ert-deftest shadow-test01-sites ()
  "Check site definitions.
Per definition, all files are identical on the different hosts of
a cluster (or site).  This is not tested here; it must be
guaranteed by the originator of a cluster definition."
  (skip-unless (file-remote-p shadow-test-remote-temporary-file-directory))

  (let ((shadow-info-file shadow-test-info-file)
	(shadow-todo-file shadow-test-todo-file)
	shadow-clusters
	cluster1 cluster2 primary1 primary2 regexp1 regexp2 mocked-input)
    (unwind-protect
	;; We must mock `read-from-minibuffer' and `read-string', in
	;; order to avoid interactive arguments.
	(cl-letf* (((symbol-function 'read-from-minibuffer)
		    (lambda (&rest args) (pop mocked-input)))
		   ((symbol-function 'read-string)
		    (lambda (&rest args) (pop mocked-input))))

	  ;; Cleanup.
	  (when (file-exists-p shadow-info-file)
	    (delete-file shadow-info-file))
	  (when (file-exists-p shadow-todo-file)
	    (delete-file shadow-todo-file))

	  ;; Define a cluster.
	  (setq cluster1 "cluster1"
		primary1 shadow-system-name
		regexp1 (shadow-regexp-superquote primary1))
	  (shadow-set-cluster cluster1 primary1 regexp1)

	  ;; A site is either a cluster identification, or a primary host.
          (should (string-equal cluster1 (shadow-site-name cluster1)))
          (should (string-equal primary1 (shadow-name-site primary1)))
          (should
           (string-equal (format "/%s:" cluster1) (shadow-name-site cluster1)))
          (should (string-equal (system-name) (shadow-site-name primary1)))
          (should
           (string-equal
            (file-remote-p shadow-test-remote-temporary-file-directory)
            (shadow-name-site
             (file-remote-p shadow-test-remote-temporary-file-directory))))
          (should
           (string-equal
            (file-remote-p shadow-test-remote-temporary-file-directory)
            (shadow-site-name
             (file-remote-p shadow-test-remote-temporary-file-directory))))

          (should (equal (shadow-site-cluster cluster1)
			 (shadow-get-cluster cluster1)))
	  (should (equal (shadow-site-cluster (shadow-name-site cluster1))
			 (shadow-get-cluster cluster1)))
	  (should (equal (shadow-site-cluster primary1)
			 (shadow-get-cluster cluster1)))
	  (should (equal (shadow-site-cluster (shadow-site-name primary1))
			 (shadow-get-cluster cluster1)))
	  (should (string-equal (shadow-site-primary cluster1) primary1))
	  (should (string-equal (shadow-site-primary primary1) primary1))

          ;; `shadow-read-site' accepts "cluster", "/cluster:",
          ;; "system", "/system:".  It shall reject bad site names.
	  (setq mocked-input
                `(,cluster1 ,(shadow-name-site cluster1)
                  ,primary1 ,(shadow-site-name primary1)
                  ,shadow-system-name "" "bad" "/bad:"))
	  (should (string-equal (shadow-read-site) cluster1))
	  (should (string-equal (shadow-read-site) (shadow-name-site cluster1)))
	  (should (string-equal (shadow-read-site) primary1))
	  (should (string-equal (shadow-read-site) (shadow-site-name primary1)))
	  (should (string-equal (shadow-read-site) shadow-system-name))
	  (should-not (shadow-read-site)) ; ""
	  (should-not (shadow-read-site)) ; "bad"
	  (should-not (shadow-read-site)) ; "/bad:"
	  (should-error (shadow-read-site)) ; no input at all

	  ;; Define a second cluster.
          (setq cluster2 "cluster2"
		primary2
		(file-remote-p shadow-test-remote-temporary-file-directory)
		regexp2 (format "^\\(%s\\|%s\\)$" shadow-system-name primary2))
	  (shadow-set-cluster cluster2 primary2 regexp2)

          ;; `shadow-site-match' shall know all different kind of site names.
          (should (shadow-site-match cluster1 cluster1))
          (should (shadow-site-match primary1 primary1))
          (should (shadow-site-match cluster1 primary1))
          (should (shadow-site-match primary1 cluster1))
          (should (shadow-site-match cluster2 cluster2))
          (should (shadow-site-match primary2 primary2))
          (should (shadow-site-match cluster2 primary2))
          (should (shadow-site-match primary2 cluster2))

          ;; The regexp of `cluster2' matches the primary of
          ;; `cluster1'.  Not vice versa.
          (should (shadow-site-match cluster2 cluster1))
          (should-not (shadow-site-match cluster1 cluster2))

          ;; If we use the primaries of a cluster, it doesn't match.
          (should-not
           (shadow-site-match (shadow-site-primary cluster2) cluster1))
          (should-not
           (shadow-site-match (shadow-site-primary cluster1) cluster2)))

      ;; Cleanup.
      (when (file-exists-p shadow-info-file)
	(delete-file shadow-info-file))
      (when (file-exists-p shadow-todo-file)
	(delete-file shadow-todo-file)))))

(ert-deftest shadow-test02-files ()
  "Check file manipulation functions."
  (skip-unless (file-remote-p shadow-test-remote-temporary-file-directory))

  (let ((shadow-info-file shadow-test-info-file)
	(shadow-todo-file shadow-test-todo-file)
	shadow-clusters
	cluster primary regexp file hup)
    (unwind-protect
	(progn
	  ;; Cleanup.
	  (when (file-exists-p shadow-info-file)
	    (delete-file shadow-info-file))
	  (when (file-exists-p shadow-todo-file)
	    (delete-file shadow-todo-file))

	  ;; Define a cluster.
	  (setq cluster "cluster"
		primary shadow-system-name
		regexp (shadow-regexp-superquote primary)
                file (make-temp-name
                      (expand-file-name
                       "shadowfile-tests" temporary-file-directory)))
	  (shadow-set-cluster cluster primary regexp)

          ;; The constant structure to compare with.
          (setq hup (make-tramp-file-name :host (system-name) :localname file))

          ;; The structure a local file is transformed in.
          (should (equal (shadow-parse-name file) hup))
          (should (equal (shadow-parse-name (concat "/" cluster ":" file)) hup))
          (should (equal (shadow-parse-name (concat primary file)) hup))

          ;; A local file name is kept.
          (should
           (string-equal (shadow-local-file file) file))
          ;; A file on this cluster is also local.
          (should
           (string-equal
	    (shadow-local-file (concat "/" cluster ":" file)) file))
          ;; A file on the primary host is also local.
          (should
           (string-equal (shadow-local-file (concat primary file)) file))

	  ;; Redefine the cluster.
	  (setq primary
		(file-remote-p shadow-test-remote-temporary-file-directory)
		regexp (shadow-regexp-superquote primary))
	  (shadow-set-cluster cluster primary regexp)

          ;; The structure of the local file is still the same.
          (should (equal (shadow-parse-name file) hup))
          ;; The cluster name must be used.
          (setf (tramp-file-name-host hup) cluster)
          (should (equal (shadow-parse-name (concat "/" cluster ":" file)) hup))
          ;; The structure of a remote file is different.
          (should
           (equal (shadow-parse-name (concat primary file))
                  (tramp-dissect-file-name (concat primary file))))

          ;; A local file is still local.
          (should (shadow-local-file file))
          ;; A file on this cluster is not local.
          (should-not (shadow-local-file (concat "/" cluster ":" file)))
          ;; A file on the primary host is not local.
          (should-not (shadow-local-file (concat primary file)))
	  ;; There's no error on wrong FILE.
	  (should-not (shadow-local-file nil)))

      ;; Cleanup.
      (when (file-exists-p shadow-info-file)
	(delete-file shadow-info-file))
      (when (file-exists-p shadow-todo-file)
	(delete-file shadow-todo-file)))))

(ert-deftest shadow-test03-expand-cluster-in-file-name ()
  "Check canonical file name of a cluster or site."
  (skip-unless (file-remote-p shadow-test-remote-temporary-file-directory))

  (let ((shadow-info-file shadow-test-info-file)
	(shadow-todo-file shadow-test-todo-file)
	shadow-clusters
	cluster primary regexp file1 file2)
    (unwind-protect
	(progn
	  ;; Cleanup.
	  (when (file-exists-p shadow-info-file)
	    (delete-file shadow-info-file))
	  (when (file-exists-p shadow-todo-file)
	    (delete-file shadow-todo-file))

	  ;; Define a cluster.
	  (setq cluster "cluster"
		primary shadow-system-name
		regexp (shadow-regexp-superquote primary))
	  (shadow-set-cluster cluster primary regexp)

	  (setq file1
		(make-temp-name
		 (expand-file-name "shadowfile-tests" temporary-file-directory))
		file2
		(make-temp-name
		 (expand-file-name
		  "shadowfile-tests"
		  shadow-test-remote-temporary-file-directory)))

          ;; A local file name is kept.
          (should
           (string-equal (shadow-expand-cluster-in-file-name file1) file1))
          ;; A remote file is kept.
          (should
           (string-equal (shadow-expand-cluster-in-file-name file2) file2))
          ;; A cluster name is expanded to the primary name.
          (should
           (string-equal
            (shadow-expand-cluster-in-file-name (format "/%s:%s" cluster file1))
            (shadow-expand-cluster-in-file-name (concat primary file1))))
          ;; A primary name is expanded if it is a local file name.
          (should
           (string-equal
            (shadow-expand-cluster-in-file-name (concat primary file1)) file1))

	  ;; Redefine the cluster.
	  (setq primary
		(file-remote-p shadow-test-remote-temporary-file-directory)
		regexp (shadow-regexp-superquote primary))
	  (shadow-set-cluster cluster primary regexp)

          ;; A cluster name is expanded to the primary name.
          (should
           (string-equal
            (shadow-expand-cluster-in-file-name (format "/%s:%s" cluster file1))
            (shadow-expand-cluster-in-file-name (concat primary file1))))
          ;; A primary name is not expanded if it isn't is a local file name.
          (should
           (string-equal
            (shadow-expand-cluster-in-file-name (concat primary file1))
            (concat primary file1))))

      ;; Cleanup.
      (when (file-exists-p shadow-info-file)
	(delete-file shadow-info-file))
      (when (file-exists-p shadow-todo-file)
	(delete-file shadow-todo-file)))))

(ert-deftest shadow-test04-contract-file-name ()
  "Check canonical file name of a cluster or site."
  (skip-unless (file-remote-p shadow-test-remote-temporary-file-directory))

  (let ((shadow-info-file shadow-test-info-file)
	(shadow-todo-file shadow-test-todo-file)
	shadow-clusters
	cluster primary regexp file)
    (unwind-protect
	(progn
	  ;; Cleanup.
	  (when (file-exists-p shadow-info-file)
	    (delete-file shadow-info-file))
	  (when (file-exists-p shadow-todo-file)
	    (delete-file shadow-todo-file))

	  ;; Define a cluster.
	  (setq cluster "cluster"
		primary shadow-system-name
		regexp (shadow-regexp-superquote primary)
                file (make-temp-name
                      (expand-file-name
                       "shadowfile-tests" temporary-file-directory)))
	  (shadow-set-cluster cluster primary regexp)

          ;; The cluster name is prepended for local files.
          (should
           (string-equal
            (shadow-contract-file-name file) (concat "/cluster:" file)))
          ;; A cluster file name is preserved.
          (should
           (string-equal
            (shadow-contract-file-name (concat "/cluster:" file))
            (concat "/cluster:" file)))
          ;; `shadow-system-name' is mapped to the cluster.
          (should
           (string-equal
            (shadow-contract-file-name (concat shadow-system-name file))
            (concat "/cluster:" file)))

	  ;; Redefine the cluster.
	  (setq primary
		(file-remote-p shadow-test-remote-temporary-file-directory)
		regexp (shadow-regexp-superquote primary))
	  (shadow-set-cluster cluster primary regexp)

          ;; A remote file name is mapped to the cluster.
          (should
           (string-equal
            (shadow-contract-file-name
             (concat
              (file-remote-p shadow-test-remote-temporary-file-directory) file))
            (concat "/cluster:" file))))

      ;; Cleanup.
      (when (file-exists-p shadow-info-file)
	(delete-file shadow-info-file))
      (when (file-exists-p shadow-todo-file)
	(delete-file shadow-todo-file)))))

(ert-deftest shadow-test05-file-match ()
  "Check `shadow-same-site' and `shadow-file-match'."
  (skip-unless (file-remote-p shadow-test-remote-temporary-file-directory))

  (let ((shadow-info-file shadow-test-info-file)
	(shadow-todo-file shadow-test-todo-file)
	shadow-clusters
	cluster primary regexp file)
    (unwind-protect
	(progn
	  ;; Cleanup.
	  (when (file-exists-p shadow-info-file)
	    (delete-file shadow-info-file))
	  (when (file-exists-p shadow-todo-file)
	    (delete-file shadow-todo-file))

	  ;; Define a cluster.
	  (setq cluster "cluster"
		primary shadow-system-name
		regexp (shadow-regexp-superquote primary)
                file (make-temp-name
                      (expand-file-name
                       "shadowfile-tests" temporary-file-directory)))
	  (shadow-set-cluster cluster primary regexp)

          (should (shadow-same-site (shadow-parse-name "/cluster:") file))
          (should
	   (shadow-same-site (shadow-parse-name shadow-system-name) file))
          (should (shadow-same-site (shadow-parse-name file) file))

          (should
	   (shadow-file-match
	    (shadow-parse-name (concat "/cluster:" file)) file))
          (should
	   (shadow-file-match
	    (shadow-parse-name (concat shadow-system-name file)) file))
          (should (shadow-file-match (shadow-parse-name file) file))

	  ;; Redefine the cluster.
	  (setq primary
		(file-remote-p shadow-test-remote-temporary-file-directory)
		regexp (shadow-regexp-superquote primary))
	  (shadow-set-cluster cluster primary regexp)

          (should
	   (shadow-file-match
	    (shadow-parse-name
	     (concat
	      (file-remote-p shadow-test-remote-temporary-file-directory)
	      file))
	    file)))

      ;; Cleanup.
      (when (file-exists-p shadow-info-file)
	(delete-file shadow-info-file))
      (when (file-exists-p shadow-todo-file)
	(delete-file shadow-todo-file)))))

(ert-deftest shadow-test06-literal-groups ()
  "Check literal group definitions."
  (skip-unless (file-remote-p shadow-test-remote-temporary-file-directory))

  (let ((shadow-info-file shadow-test-info-file)
	(shadow-todo-file shadow-test-todo-file)
	shadow-clusters shadow-literal-groups
	cluster1 cluster2 primary regexp file1 file2 mocked-input)
    (unwind-protect
	;; We must mock `read-from-minibuffer' and `read-string', in
	;; order to avoid interactive arguments.
	(cl-letf* (((symbol-function 'read-from-minibuffer)
		    (lambda (&rest args) (pop mocked-input)))
		   ((symbol-function 'read-string)
		    (lambda (&rest args) (pop mocked-input))))

	  ;; Cleanup.
	  (when (file-exists-p shadow-info-file)
	    (delete-file shadow-info-file))
	  (when (file-exists-p shadow-todo-file)
	    (delete-file shadow-todo-file))

	  ;; Define clusters.
	  (setq cluster1 "cluster1"
		primary shadow-system-name
		regexp (shadow-regexp-superquote primary))
	  (shadow-set-cluster cluster1 primary regexp)

	  (setq cluster2 "cluster2"
		primary
		(file-remote-p shadow-test-remote-temporary-file-directory)
		regexp (format "^\\(%s\\|%s\\)$" shadow-system-name primary))
	  (shadow-set-cluster cluster2 primary regexp)

	  ;; Define a literal group.
	  (setq file1
		(make-temp-name
		 (expand-file-name "shadowfile-tests" temporary-file-directory))
		file2
		(make-temp-name
		 (expand-file-name
		  "shadowfile-tests"
		  shadow-test-remote-temporary-file-directory))
		mocked-input `(,cluster1 ,file1 ,cluster2 ,file2 ,(kbd "RET")))
	  (with-temp-buffer
	    (setq-local buffer-file-name file1)
	    (call-interactively 'shadow-define-literal-group))

          ;; `shadow-literal-groups' is a list of lists.
          (should (consp shadow-literal-groups))
          (should (consp (car shadow-literal-groups)))
          (should-not (cdr shadow-literal-groups))

	  (should (member (format "/%s:%s" cluster1 (file-local-name file1))
                          (car shadow-literal-groups)))
	  (should (member (format "/%s:%s" cluster2 (file-local-name file2))
                          (car shadow-literal-groups))))

      ;; Cleanup.
      (when (file-exists-p shadow-info-file)
	(delete-file shadow-info-file))
      (when (file-exists-p shadow-todo-file)
	(delete-file shadow-todo-file)))))

(ert-deftest shadow-test07-regexp-groups ()
  "Check regexp group definitions."
  (skip-unless (file-remote-p shadow-test-remote-temporary-file-directory))

  (let ((shadow-info-file shadow-test-info-file)
	(shadow-todo-file shadow-test-todo-file)
	shadow-clusters shadow-regexp-groups
	cluster1 cluster2 primary regexp file mocked-input)
    (unwind-protect
	;; We must mock `read-from-minibuffer' and `read-string', in
	;; order to avoid interactive arguments.
	(cl-letf* (((symbol-function 'read-from-minibuffer)
		    (lambda (&rest args) (pop mocked-input)))
		   ((symbol-function 'read-string)
		    (lambda (&rest args) (pop mocked-input))))

	  ;; Cleanup.
	  (when (file-exists-p shadow-info-file)
	    (delete-file shadow-info-file))
	  (when (file-exists-p shadow-todo-file)
	    (delete-file shadow-todo-file))

	  ;; Define clusters.
	  (setq cluster1 "cluster1"
		primary shadow-system-name
		regexp (shadow-regexp-superquote primary))
	  (shadow-set-cluster cluster1 primary regexp)

	  (setq cluster2 "cluster2"
		primary
		(file-remote-p shadow-test-remote-temporary-file-directory)
		regexp (format "^\\(%s\\|%s\\)$" shadow-system-name primary))
	  (shadow-set-cluster cluster2 primary regexp)

	  ;; Define a regexp group.
	  (setq file
		(make-temp-name
		 (expand-file-name "shadowfile-tests" temporary-file-directory))
		mocked-input `(,(shadow-regexp-superquote file)
                               ,cluster1 ,cluster2 ,(kbd "RET")))
	  (with-temp-buffer
	    (setq-local buffer-file-name nil)
	    (call-interactively 'shadow-define-regexp-group))

          ;; `shadow-regexp-groups' is a list of lists.
          (should (consp shadow-regexp-groups))
          (should (consp (car shadow-regexp-groups)))
          (should-not (cdr shadow-regexp-groups))

	  (should
           (member
            (concat
             (shadow-site-primary cluster1) (shadow-regexp-superquote file))
            (car shadow-regexp-groups)))
	  (should
           (member
            (concat
             (shadow-site-primary cluster2) (shadow-regexp-superquote file))
            (car shadow-regexp-groups))))

      ;; Cleanup.
      (when (file-exists-p shadow-info-file)
	(delete-file shadow-info-file))
      (when (file-exists-p shadow-todo-file)
	(delete-file shadow-todo-file)))))

(ert-deftest shadow-test08-shadow-todo ()
  "Check that needed shadows are added to todo."
  (skip-unless (file-remote-p shadow-test-remote-temporary-file-directory))

  (let ((backup-inhibited t)
        (shadow-info-file shadow-test-info-file)
	(shadow-todo-file shadow-test-todo-file)
        (shadow-inhibit-message t)
	shadow-clusters shadow-literal-groups shadow-regexp-groups
        shadow-files-to-copy
	cluster1 cluster2 primary regexp file)
    (unwind-protect
        (condition-case err
        (progn
	  ;; Cleanup.
	  (when (file-exists-p shadow-info-file)
	    (delete-file shadow-info-file))
	  (when (file-exists-p shadow-todo-file)
	    (delete-file shadow-todo-file))

          (message "Point 1")
          ;; Define clusters.
	  (setq cluster1 "cluster1"
		primary shadow-system-name
		regexp (shadow-regexp-superquote primary))
	  (shadow-set-cluster cluster1 primary regexp)

	  (setq cluster2 "cluster2"
		primary
		(file-remote-p shadow-test-remote-temporary-file-directory)
		regexp (shadow-regexp-superquote primary))
	  (shadow-set-cluster cluster2 primary regexp)

          (message "Point 2")
	  ;; Define a literal group.
	  (setq file
		(make-temp-name
		 (expand-file-name "shadowfile-tests" temporary-file-directory))
                shadow-literal-groups
                `((,(concat "/cluster1:" file) ,(concat "/cluster2:" file))))

          (message "Point 3")
          ;; Save file from "cluster1" definition.
          (with-temp-buffer
            (setq buffer-file-name file)
            (insert "foo")
            (save-buffer))
          (message "%s" file)
          (message "%s" (shadow-contract-file-name (concat "/cluster2:" file)))
          (message "%s" shadow-files-to-copy)
	  (should
           (member
            (cons file (shadow-contract-file-name (concat "/cluster2:" file)))
            shadow-files-to-copy))

          (message "Point 4")
          ;; Save file from "cluster2" definition.
          (with-temp-buffer
           (message "Point 4.1")
           (setq buffer-file-name (concat (shadow-site-primary cluster2) file))
          (message "Point 4.2")
            (insert "foo")
            (save-buffer))
          (message "Point 4.3")
          (message "%s" (shadow-site-primary cluster2))
          (message "%s" (shadow-contract-file-name (concat "/cluster1:" file)))
          (message "%s" shadow-files-to-copy)
	  (should
           (member
            (cons
             (concat (shadow-site-primary cluster2) file)
             (shadow-contract-file-name (concat "/cluster1:" file)))
            shadow-files-to-copy))

          (message "Point 5")
	  ;; Define a regexp group.
	  (setq shadow-files-to-copy nil
                shadow-regexp-groups
                `((,(concat (shadow-site-primary cluster1)
                            (shadow-regexp-superquote file))
                   ,(concat (shadow-site-primary cluster2)
                            (shadow-regexp-superquote file)))))

          (message "Point 6")
          ;; Save file from "cluster1" definition.
          (with-temp-buffer
            (setq buffer-file-name file)
            (insert "foo")
            (save-buffer))
	  (should
           (member
            (cons file (shadow-contract-file-name (concat "/cluster2:" file)))
            shadow-files-to-copy))

          (message "Point 7")
          ;; Save file from "cluster2" definition.
          (with-temp-buffer
            (setq buffer-file-name (concat (shadow-site-primary cluster2) file))
            (insert "foo")
            (save-buffer))
	  (should
           (member
            (cons
             (concat (shadow-site-primary cluster2) file)
             (shadow-contract-file-name (concat "/cluster1:" file)))
            shadow-files-to-copy)))
        (error (message "Error: %s" err) (signal (car err) (cdr err))))

      ;; Cleanup.
      (when (file-exists-p shadow-info-file)
	(delete-file shadow-info-file))
      (when (file-exists-p shadow-todo-file)
	(delete-file shadow-todo-file))
      (ignore-errors
        (when (file-exists-p file)
	  (delete-file file)))
      (ignore-errors
        (when (file-exists-p (concat (shadow-site-primary cluster2) file))
	  (delete-file (concat (shadow-site-primary cluster2) file)))))))

(ert-deftest shadow-test09-shadow-copy-files ()
  "Check that needed shadow files are copied."
  (skip-unless (file-remote-p shadow-test-remote-temporary-file-directory))

  (let ((backup-inhibited t)
        (shadow-info-file shadow-test-info-file)
	(shadow-todo-file shadow-test-todo-file)
        (shadow-inhibit-message t)
        (shadow-noquery t)
        shadow-clusters shadow-files-to-copy
	cluster1 cluster2 primary regexp file mocked-input)
    (unwind-protect
	(progn
	  ;; Cleanup.
	  (when (file-exists-p shadow-info-file)
	    (delete-file shadow-info-file))
	  (when (file-exists-p shadow-todo-file)
	    (delete-file shadow-todo-file))
          (when (buffer-live-p shadow-todo-buffer)
            (with-current-buffer shadow-todo-buffer (erase-buffer)))

          ;; Define clusters.
	  (setq cluster1 "cluster1"
		primary shadow-system-name
		regexp (shadow-regexp-superquote primary))
	  (shadow-set-cluster cluster1 primary regexp)

	  (setq cluster2 "cluster2"
		primary
		(file-remote-p shadow-test-remote-temporary-file-directory)
		regexp (shadow-regexp-superquote primary))
	  (shadow-set-cluster cluster2 primary regexp)

	  ;; Define files to copy.
	  (setq file
		(make-temp-name
		 (expand-file-name "shadowfile-tests" temporary-file-directory))
                shadow-literal-groups
                `((,(concat "/cluster1:" file) ,(concat "/cluster2:" file)))
                shadow-regexp-groups
                `((,(concat (shadow-site-primary cluster1)
                            (shadow-regexp-superquote file))
                   ,(concat (shadow-site-primary cluster2)
                            (shadow-regexp-superquote file))))
		mocked-input `(,(concat (shadow-site-primary cluster2) file)
                               ,file))

          ;; Save files.
          (with-temp-buffer
            (setq buffer-file-name file)
            (insert "foo")
            (save-buffer))
          (with-temp-buffer
            (setq buffer-file-name (concat (shadow-site-primary cluster2) file))
            (insert "foo")
            (save-buffer))

	  ;; We must mock `write-region', in order to check proper
	  ;; action.
          (add-function
           :before (symbol-function 'write-region)
	   (lambda (&rest args)
             (when (and (buffer-file-name) mocked-input)
               (should (equal (buffer-file-name) (pop mocked-input)))))
           '((name . "write-region-mock")))

          ;; Copy the files.
          (shadow-copy-files 'noquery)
          (should-not shadow-files-to-copy)
          (with-current-buffer shadow-todo-buffer
            (goto-char (point-min))
            (should
             (looking-at (regexp-quote "(setq shadow-files-to-copy nil)")))))

      ;; Cleanup.
      (remove-function (symbol-function 'write-region) "write-region-mock")
      (when (file-exists-p shadow-info-file)
	(delete-file shadow-info-file))
      (when (file-exists-p shadow-todo-file)
	(delete-file shadow-todo-file))
      (ignore-errors
        (when (file-exists-p file)
	  (delete-file file)))
      (ignore-errors
        (when (file-exists-p (concat (shadow-site-primary cluster2) file))
	  (delete-file (concat (shadow-site-primary cluster2) file)))))))

(defun shadowfile-test-all (&optional interactive)
  "Run all tests for \\[shadowfile]."
  (interactive "p")
  (if interactive
      (ert-run-tests-interactively "^shadowfile-")
    (ert-run-tests-batch "^shadowfile-")))

(let ((shadow-info-file shadow-test-info-file)
      (shadow-todo-file shadow-test-todo-file))
  (shadow-initialize))

(provide 'shadowfile-tests)
;;; shadowfile-tests.el ends here
