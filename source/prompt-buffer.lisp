;;;; SPDX-FileCopyrightText: Atlas Engineer LLC
;;;; SPDX-License-Identifier: BSD-3-Clause

(in-package :nyxt)

(defmacro define-function (name args docstring &body body)
  "Eval ARGS and DOCSTRING then define function over the resulting lambda list
and string.
All ARGS are declared as `ignorable'."
  (let ((evaluated-args (eval args))
        (evaluated-docstring (eval docstring)))
    `(defun ,name ,evaluated-args
       ,evaluated-docstring
       (declare (ignorable ,@(set-difference (mapcar (lambda (arg) (if (listp arg) (first arg) arg))
                                                     evaluated-args)
                                             lambda-list-keywords)))
       ,@body)))

(sera:eval-always
  (define-class prompt-buffer (user-internal-buffer)
    ((prompter (error "Prompter required") ; TODO: Inherit instead?
               :type prompter:prompter)
     (default-modes '(prompt-buffer-mode))
     ;; TODO: Need a changed-callback?
     ;; TODO: Need a invisible-input-p slot?
     (invisible-input-p nil
                        :documentation "If non-nil, input is replaced by placeholder character.
;; This is useful to conceal passwords.")
     (hide-suggestion-count-p nil       ; TODO: Move to `prompter' library?
                              :documentation "Show the number of chosen suggestions
;; inside brackets. It can be useful to disable, for instance for a yes/no question.")
     ;; TODO: If we move selection cursor to `prompter' library, then it can be
     ;; restored when resuming.
     ;; (suggestion-head 0
     ;;                  :export nil)
     ;; (suggestion-cursor 0
     ;;                    :export nil)
     (content ""
              :accessor nil
              :export nil
              :documentation "The HTML content of the minibuffer.")
     ;; TODO: Need max-lines?
     ;; (max-lines 10
     ;;               :documentation "Max number of suggestion lines to show.
     ;; You will want edit this to match the changes done to `style'.")
     (style #.(cl-css:css
               '((* :font-family "monospace,monospace"
                    :font-size "14px"
                    :line-height "18px")
                 (body :border-top "4px solid dimgray"
                       :margin "0"
                       :padding "0 6px")
                 ("#container" :display "flex"
                               :flex-flow "column"
                               :height "100%")
                 ("#input" :padding "6px 0"
                           :border-bottom "solid 1px lightgray")
                 ("#suggestions" :flex-grow "1"
                                 :overflow-y "auto"
                                 :overflow-x "auto")
                 ("#cursor" :background-color "gray"
                            :color "white")
                 ("#prompt" :padding-right "4px"
                            :color "dimgray")
                 (ul :list-style "none"
                     :padding "0"
                     :margin "0")
                 (li :padding "2px")
                 (.marked :background-color "darkgray"
                          :font-weight "bold"
                          :color "white")
                 (.selected :background-color "gray"
                            :color "white")))
            :documentation "The CSS applied to a minibuffer when it is set-up.")
     (override-map (let ((map (make-keymap "overide-map")))
                     (define-key map
                       "escape"
                       ;; We compute symbol at runtime because
                       ;; nyxt/minibuffer-mode does not exist at
                       ;; compile-time since it's loaded afterwards.
                       (find-symbol (string 'cancel-input)
                                    (find-package 'nyxt/prompt-buffer-mode))))
                   :type keymap:keymap
                   :documentation "Keymap that takes precedence over all modes' keymaps."))
    (:export-class-name-p t)
    (:export-accessor-names-p t)
    (:accessor-name-transformer #'class*:name-identity)
    (:documentation "The prompt buffer is the interface for user interactions.
Each prompt spawns a new object: this makes it possible to nest prompts , such
as invoking `prompt-history'.

A prompt query is typically done as follows:

\(let ((tags (prompt-minibuffer
              :input-prompt \"Space-separated tag (s) \"
              :default-modes '(set-tag-mode minibuffer-mode)
              :suggestion-function (tag-suggestion-filter))))
  ;; Write form here in which `tags' is bound to the resulting element(s).
  )")))

(define-user-class prompt-buffer)

(defmethod initialize-instance :after ((prompt-buffer prompt-buffer) &key) ; TODO: Merge in `make-prompt-buffer'?
  (hooks:run-hook (minibuffer-make-hook *browser*) prompt-buffer) ; TODO: Rename `minibuffer'.
  ;; We don't want to show the input in the suggestion list when invisible.
  (when (invisible-input-p prompt-buffer)
    (dolist (source (prompter:sources (prompter prompt-buffer)))
      ;; This way the minibuffer won't display the input as a suggestion.
      (setf (prompter:must-match-p source) t)))
  (initialize-modes prompt-buffer))

(export-always 'make-prompt-buffer)
(define-function make-prompt-buffer (append
                                     '(&rest args)
                                     `(&key (window (current-window))
                                            ,@(public-initargs 'prompt-buffer)))
  "TODO: Complete me!"
  (let* ((initargs (alex:remove-from-plist args :window)) ; TODO: Make window a slot or prompt-buffer? That would simplify `make-prompt-buffer' args.
         (prompt-buffer (apply #'make-instance 'prompt-buffer initargs)))
    ;; (update-display prompt-buffer) ; TODO: Remove when sure.
    (push prompt-buffer (active-minibuffers window))
    (show-prompt-buffer)                              ; TODO: Show should probably take an argument, no?
    ;; TODO: Add method that returns if there is only 1 source with no filter.
    ;; (apply #'show
    ;;        (unless (prompter:filter prompt-buffer)
    ;;          ;; We don't need so much height since there is no suggestion to display.
    ;;          (list :height (minibuffer-open-single-line-height (current-window)))))
    ))

(defun show-prompt-buffer (&key (prompt-buffer (first (active-minibuffers (current-window)))) height)
  "Show the last active prompt-buffer, if any."
  (when prompt-buffer
    (erase-document prompt-buffer)      ; TODO: When to erase?
    (update-display prompt-buffer)
    (ffi-window-set-prompt-buffer-height
     (current-window)
     (or height
         (minibuffer-open-height (current-window)))))) ; TODO: Rename `minibuffer'.

(defmethod state-changed ((prompt-buffer prompt-buffer)) ; TODO: Remove when done.
  nil)

(export-always 'hide-prompt-buffer)
(defun hide-prompt-buffer (prompt-buffer) ; TODO: Rename `hide'
  "Hide PROMPT-BUFFER and display next active one, if any."
  (prompter:destructor (nyxt:prompter prompt-buffer))
  ;; Note that PROMPT-BUFFER is not necessarily first in the list, e.g. a new
  ;; prompt-buffer was invoked before the old one reaches here.
  (alex:deletef (active-minibuffers (current-window)) prompt-buffer)
  (if (active-minibuffers (current-window))
      (progn
        ;; TODO: Remove when done with `minibuffer'.
        (if (prompt-buffer-p (first (active-minibuffers (current-window))))
            (show-prompt-buffer)
            (show))
        ;; TODO: Remove?
        ;; We need to refresh so that the nested prompt-buffers don't have to do it.
        ;; (state-changed (first (active-minibuffers (current-window))))
        ;; (update-display (first (active-minibuffers (current-window))))
        )
      (progn
        (ffi-window-set-prompt-buffer-height (current-window) 0))))

(export-always 'evaluate-script)
(defmethod evaluate-script ((prompt-buffer prompt-buffer) script) ; TODO: Remove?
  "Evaluate SCRIPT into PROMPT-BUFFER's webview.
The new webview HTML content is set as the MINIBUFFER's `content'."
  (when prompt-buffer
    (let ((new-content (str:concat script (ps:ps (ps:chain document body |outerHTML|))))) ; TODO: Why do we postfix with this (ps:ps ... |outerHTML|)?
      (ffi-minibuffer-evaluate-javascript-async
       (current-window)
       new-content))))

(defmethod erase-document ((prompt-buffer prompt-buffer)) ; TODO: Remove, empty automatically when `content' is set?
  (evaluate-script prompt-buffer (ps:ps
                                   (ps:chain document (open))
                                   (ps:chain document (close)))))

(defmethod generate-prompt-html ((prompt-buffer prompt-buffer))
  (markup:markup
   (:head ;; (:style (style prompt-buffer))
    )
   (:body
    (:div :id "container"
          (:div :id "prompt-input"
                (:span :id "prompt" (prompter:prompt (prompter prompt-buffer)))
                ;; TODO: See minibuffer `generate-prompt-html' to print the counts.
                (:span :id "prompt-extra" "[?/?]")
                (:input :type "text" :id "input"))
          ;; TODO: Support multi columns and sources.
          (:div :id "suggestions"
                ;; (:table
                ;;  (loop repeat 10 ;; TODO: Only print as many lines as fit the height.
                ;;        for suggestion in (prompter:suggestions source)
                ;;        collect (markup:markup (:tr (:td (object-display (prompter:value suggestion)))))))
                )))))


(defmethod update-suggestion-html ((prompt-buffer prompt-buffer))
  ;; TODO: Add HTML to set prompt extra.
  (let ((source (first (prompter:sources (prompter prompt-buffer)))))
    (evaluate-script
     prompt-buffer
     (ps:ps
       (setf (ps:chain document (get-element-by-id "suggestions") |innerHTML|)
             (ps:lisp
              (markup:markup
               (:table
                (loop repeat 10 ;; TODO: Only print as many lines as fit the height.
                      for suggestion in (prompter:suggestions source)
                      collect (markup:markup (:tr (:td (object-display (prompter:value suggestion))))))))))))))

(defmethod update-display ((prompt-buffer prompt-buffer)) ; TODO: Merge into `show'?
  ;; TODO: Finish me!
  (ffi-minibuffer-evaluate-javascript-async ; TODO: Replace with `evaluate-script'?  Rename the latter?
   (current-window)
   (ps:ps (ps:chain document
                    (write (ps:lisp (str:concat (generate-prompt-html prompt-buffer)))))))
  (update-suggestion-html prompt-buffer))

(export-always 'get-marked-suggestions)
(defmethod get-marked-suggestions ((prompt-buffer prompt-buffer))
  "Return the list of strings for the marked suggestion in the minibuffer."
  (mapcar #'object-string (alex:mappend #'prompter:marked-suggestions
                                        (prompter:sources prompt-buffer))))

(export-always 'prompt)
(defun prompt (&key prompter prompt-buffer)
  "Open the prompt buffer, ready for user input.
ARGS are passed to the prompt-buffer constructor.
Example use:

\(prompt
  :prompter (sources (list (make-instance 'prompter:prompter-source :filter #'my-suggestion-filter)))
  :prompt-buffer )

See the documentation of `prompt-buffer' to know more about the options."
  (let ((prompt (apply #'prompter:make prompter)))
    (ffi-within-renderer-thread
     *browser*
     (lambda ()
       (apply 'make-prompt-buffer (append (list :prompter prompt)
                                          prompt-buffer))))
    ;; Wait until it's destroyed and get the selections from `return-selection'.
    (calispel:fair-alt
      ((calispel:? (prompter:result-channel prompt) results)
       results)
      ((calispel:? (prompter:interrupt-channel prompt))
       (error 'nyxt-prompt-buffer-canceled)))))

(export-always 'prompter-if-confirm)    ; TODO: Rename to `if-confirm' once `minibuffer' is gone.
(defmacro prompter-if-confirm (prompt yes-form &optional no-form)
  "Ask the user for confirmation before executing either YES-FORM or NO-FORM.
YES-FORM is executed on  \"yes\" answer, NO-FORM -- on \"no\".
PROMPT is a list fed to `format nil'.

Example usage defaulting to \"no\":

\(let ((*yes-no-choices* '(:no \"no\" :yes \"yes\")))
  (if-confirm (\"Are you sure to kill ~a buffers?\" count)
     (delete-buffers)))"
  ;; TODO: Can we keep the `*yes-no-choices*' customization option?
  `(let ((answer (prompt
                  :input-prompt (format nil ,@prompt)
                  :suggestion-function (yes-no-suggestion-filter)
                  :hide-suggestion-count-p t)))
     (if (confirmed-p answer)
         ,yes-form
         ,no-form)))