;; Emacs settings
;; $Id$

;; EDITING
;; Wrap text at the 78th column
(setq-default auto-fill-function 'do-auto-fill)
(setq-default fill-column 78)
;; Do not use tabs for indentation (always insert spaces)
(setq-default indent-tabs-mode nil)
;; Show line and column numbers
(setq line-number-mode t)
(setq column-number-mode t)
;; Highlight the selected region
(setq transient-mark-mode t)
;; Highlight matching parens
(setq show-paren-mode t)
;; Enable syntax highlighting if available
(cond ((fboundp 'global-font-lock-mode) (global-font-lock-mode t)))
(setq-default font-lock-maximum-decoration 2)
;; (add-hook 'c-mode-common-hook
;;   '(lambda ()
;;      ;; Enable hungry whitespace deletion
;;      (c-toggle-auto-hungry-state t)
;;      ;; Enable automatic syntactic newlines
;;      ;;(c-toggle-auto-state t)
;;      )
;; )
;; Create a useful key binding for goto-line
(global-set-key "\M-g" 'goto-line)

;; ENVIRONMENT
;; Use a visible bell
(setq visible-bell t)
;; Disable menu bar in console mode (GNU Emacs only)
(if (not window-system) (menu-bar-mode nil))
;; Position the scroll bar on the right-hand side
(cond ((fboundp 'set-scroll-bar-mode) (set-scroll-bar-mode 'right)))
;; Use the system clipboard
;;(setq x-select-enable-clipboard t)

;; PROGRAMMING
;; Use Stroustrup style for C and C++, Java style for Java
(setq c-default-style '((java-mode . "java") (other . "stroustrup")))
;; Default to Bourne shell for new shell scripts
(defvar sh-shell-file "sh")
;; Use third-party PHP mode for PHP if available
(autoload 'php-mode "php-mode")
(setq auto-mode-alist
      (append '(("\\.php" . php-mode)) auto-mode-alist))
