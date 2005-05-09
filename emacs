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
;; Fix the shell indentation
(add-hook 'sh-mode-hook
	  '(lambda ()
	     (setq sh-basic-offset 8)
	     (setq sh-indent-for-do 0)
	     (setq sh-indent-after-do '+)
	     (setq sh-indent-for-then 0)))

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

;; Custom function to determine configuration file
;; (hopefully fixes custom settings overwriting symlinks)
(defun custom-file ()
  "Return the file name for saving customizations."
  (file-chase-links
   (or custom-file
       (let ((user-init-file user-init-file)
             (default-init-file
               (if (eq system-type 'ms-dos) "~/_emacs" "~/.emacs")))
         (when (null user-init-file)
           (if (or (file-exists-p default-init-file)
                   (and (eq system-type 'windows-nt)
                        (file-exists-p "~/_emacs")))
               ;; Started with -q, i.e. the file containing
               ;; Custom settings hasn't been read.  Saving
               ;; settings there would overwrite other settings.
               (error "Saving settings from \"emacs -q\" would overwrite existing customizations"))
           (setq user-init-file default-init-file))
         user-init-file))))


