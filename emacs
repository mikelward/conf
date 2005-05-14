;; -*- mode: emacs-lisp -*-
;; $Id$
;; Emacs settings

;; DISPLAY
;; Show line and column numbers
(setq line-number-mode t)
(setq column-number-mode t)

;; Highlight the selected region
(setq transient-mark-mode t)

;; Highlight matching parens
;; XXX: Why is this a function instead of a setting?
(show-paren-mode t)

;; Enable syntax highlighting if available
(if (fboundp 'global-font-lock-mode) (global-font-lock-mode t))

;; Use minimal syntax highlighting
(setq-default font-lock-maximum-decoration nil)

;; Disable menu bar in console mode (GNU Emacs only)
(if (not window-system) (menu-bar-mode nil))

;; Position the scroll bar on the right-hand side
(if (fboundp 'set-scroll-bar-mode) (set-scroll-bar-mode 'right))

;; EDITING
;; Do not use tabs for indentation (always insert spaces)
(setq-default indent-tabs-mode nil)

;; ENVIRONMENT
;; Use a visible bell
(setq visible-bell t)

;; FILES
;; Follow symlinks to CVS and SVN files
(setq vc-follow-symlinks t)

;; KEYS
;; Add an alternate binding for help in case C-h is unavailable
(global-set-key "\C-x\?" 'help-for-help)

;; Add a binding to go to a specified line number
(global-set-key "\C-xg" 'goto-line)

;; Add a binding to kill the current buffer
(global-set-key "\C-x\C-k" 'kill-this-buffer)

;; PROGRAMMING
;; Default to Bourne shell for new shell scripts
(setq-default sh-shell-file "sh")

;; Fix the shell indentation
(add-hook 'sh-mode-hook
	  '(lambda ()
             (setq sh-indent-comment t)
	     (setq sh-indent-for-do 0)
	     (setq sh-indent-after-do '+)
             (setq sh-indent-after-if '+)
	     (setq sh-indent-for-then 0)))

;; Use Stroustrup identation style for C and C++
(setq c-default-style '((c-mode . "stroustrup") (c++-mode . "stroustrup")))
(add-hook 'c-mode-common-hook
          '(lambda ()
             ;; Enable hungry whitespace deletion
             (c-toggle-hungry-state t)
             ;; Make new lines start at current indentation level
             (define-key c-mode-base-map "\C-m" 'c-context-line-break)))

;; Remind PHP mode to not get carried away with syntax highlighting
(add-hook 'php-mode-user-hook
          '(lambda ()
             (setq font-lock-maximum-decoration nil)))
