;; -*- mode: emacs-lisp -*-
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
;; Make C-a go to the start of the text the first time
(global-set-key "\C-a" 'my-beginning-of-line)

;; Make forward word work like other editors
(global-set-key "\M-f" 'my-forward-word)

;; Add an alternate binding for help in case C-h is unavailable
(global-set-key "\C-x\?" 'help-for-help)

;; Add a binding to go to a specified line number
(global-set-key "\C-xg" 'goto-line)

;; Make Return place point at the appropriate indentation level
(global-set-key "\C-m" 'newline-and-indent)

;; Add a binding to kill the current buffer
(global-set-key "\C-x\C-k" 'kill-this-buffer)

;; Make C-u kill a line like it does in a tty
;; TODO make kill-whole-line work more logically
(global-set-key "\C-u" 'kill-whole-line)

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

;; Use hex mode for binary files
(add-to-list 'auto-mode-alist '("\\.bin\\'" . hexl-mode))
(add-to-list 'auto-mode-alist '("\\.dat\\'" . hexl-mode))
(add-to-list 'auto-mode-alist '("\\.exe\\'" . hexl-mode))
(add-to-list 'auto-mode-alist '("\\.o\\'" . hexl-mode))

;; Remind PHP mode to not get carried away with syntax highlighting
(add-hook 'php-mode-user-hook
          '(lambda ()
             (setq font-lock-maximum-decoration nil)))

;; Make variants of word motion functions that are more typical
(defun my-forward-word () (interactive) (forward-word 2) (backward-word 1))
(defun my-backward-word ())
(defun my-kill-word ())
(defun my-backward-kill-word ())
(defun my-beginning-of-line () (interactive)
                               (if (and (eq last-command 'my-beginning-of-line)
                                        (/= (line-beginning-position) (point)))
                                   (beginning-of-line)
                                 (beginning-of-line-text)))

;; Load any local customisations
(if (file-exists-p "~/.emacs.local") (load "~/.emacs.local"))

;; Use my standard minimal highlighting
(custom-set-faces
 ;; custom-set-faces was added by Custom.
 ;; If you edit it by hand, you could mess it up, so be careful.
 ;; Your init file should contain only one such instance.
 ;; If there is more than one, they won't work right.
 '(font-lock-comment-face ((t (:foreground "#3647D9"))))
 '(font-lock-constant-face ((t nil)))
 '(font-lock-doc-face ((t (:inherit font-lock-comment-face))))
 '(font-lock-function-name-face ((t (:foreground "#ED8F23"))))
 '(font-lock-keyword-face ((t nil)))
 '(font-lock-string-face ((t (:foreground "#1F8C35"))))
 '(font-lock-type-face ((t nil)))
 '(font-lock-variable-name-face ((t nil))))
(custom-set-variables
 ;; custom-set-variables was added by Custom.
 ;; If you edit it by hand, you could mess it up, so be careful.
 ;; Your init file should contain only one such instance.
 ;; If there is more than one, they won't work right.
 )
