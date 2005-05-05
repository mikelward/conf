;; -*- mode: emacs-lisp -*-
;; $Id$
;; Emacs settings

;; EDITING
;; Wrap text at the 78th column
;;(setq-default auto-fill-function 'do-auto-fill)
;;(setq-default fill-column 78)
;; Show line and column numbers
(setq line-number-mode t)
(setq column-number-mode t)
;; Highlight the selected region
(setq transient-mark-mode t)
;; Highlight matching parens
(setq show-paren-mode t)
;; Enable syntax highlighting if available
(if (fboundp 'global-font-lock-mode) (global-font-lock-mode t))
;; Use minimal highlighting
(setq-default font-lock-maximum-decoration nil)
;; Create a useful key binding for goto-line
(global-set-key "\M-g" 'goto-line)

;; ENVIRONMENT
;; Use a visible bell
(setq visible-bell t)
;; Disable menu bar in console mode (GNU Emacs only)
(if (not window-system) (menu-bar-mode nil))
;; Position the scroll bar on the right-hand side
(if (fboundp 'set-scroll-bar-mode) (set-scroll-bar-mode 'right))
;; Use the system clipboard
;;(setq x-select-enable-clipboard t)

;; PROGRAMMING
;; Default to Bourne shell for new shell scripts
(setq-default sh-shell-file "sh")
;; Use Stroustrup identation style for C and C++
(setq c-default-style '((c-mode . "stroustrup") (c++-mode . "stroustrup")))
(add-hook 'c-mode-common-hook
          '(lambda ()
             ;; Enable hungry whitespace deletion
             (c-toggle-hungry-state t)
             ;; Disable automatic syntactic newlines
             ;;(c-toggle-auto-state nil)
             ;; Do not use tabs for indentation (always insert spaces)
             (setq indent-tabs-mode nil)
             ;; Make new lines start at current indentation level
             (define-key c-mode-base-map "\C-m" 'c-context-line-break)))
;; Use HTML mode for PHP files
(add-to-list 'auto-mode-alist '("\\.php[34]?\\'" . html-mode))