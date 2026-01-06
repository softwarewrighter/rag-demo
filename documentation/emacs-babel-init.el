;; ~/.emacs or ~/.emacs.d/init.el

;; Org-babel setup for rag-demo literate programming
(require 'org)
(require 'ob-shell)  ;; or (require 'ob-sh) for older Emacs

;; Enable languages
(org-babel-do-load-languages
 'org-babel-load-languages
 '((emacs-lisp . t)
   (shell . t)
   (python . t)))

;; Security: Don't ask for confirmation for safe languages
(setq org-confirm-babel-evaluate
      (lambda (lang body)
        (not (member lang '("shell" "sh" "bash" "emacs-lisp")))))

;; Better code block editing
(setq org-src-fontify-natively t
      org-src-tab-acts-natively t
      org-src-preserve-indentation t
      org-edit-src-content-indentation 0)

;; Useful keybindings
;; C-c C-c   Execute code block
;; C-c C-v b Execute all blocks in buffer
;; C-c C-v s Execute subtree
;; C-c '     Edit code block in native mode

;; Optional: Set default directory for shell blocks
;; (setq org-babel-default-header-args:shell
;;       '((:dir . "/home/user/rag-demo")))
