"
Prompt-toolkit application for simple chat REPL.
"

(import hy [mangle])
(require hyrule [defmain])

(import hyrule [assoc inc])
(import hyjinx.lib [first rest slurp sync-await])
(import itertools [pairwise])

(import asyncio)
(import clipman)
(import re)
(import os)
(import pansi [ansi])
(import pathlib [Path])
(import shutil [get-terminal-size])
(import shlex)

(import clipman)

(import prompt-toolkit [ANSI])
(import prompt-toolkit.application [Application get-app-or-none])
(import prompt_toolkit.layout [WindowAlign])
(import prompt_toolkit.layout.dimension [Dimension])
(import prompt-toolkit.document [Document])
(import prompt-toolkit.filters [Condition to-filter is-multiline has-focus])
(import prompt-toolkit.filters [Condition to-filter is-multiline has-focus])
(import prompt-toolkit.formatted-text [to-plain-text])
(import prompt-toolkit.key-binding [KeyBindings])
(import prompt_toolkit.key_binding.bindings.page_navigation [scroll_page_up scroll_page_down])
(import prompt-toolkit.layout.containers [HSplit VSplit Window])
(import prompt-toolkit.layout.layout [Layout])
(import prompt-toolkit.patch-stdout [patch-stdout])
;(import prompt-toolkit.styles [Style])
(import prompt-toolkit.widgets [Label HorizontalLine SearchToolbar TextArea Frame])
(import prompt-toolkit.shortcuts [input-dialog])

(import prompt-toolkit.styles.pygments [style-from-pygments-cls])
(import prompt-toolkit.lexers [PygmentsLexer])
(import pygments.lexers [MarkdownLexer])
(import pygments.styles [get-style-by-name])

(import chatthy.client [state])
(import chatthy.client.client [server-rpc])


;; TODO Ctrl-C cancel generation -- send a message, set a flag, check for each chunk.
;; TODO allow click to focus

;; * handlers, general functions
;; ----------------------------------------------------------------------------

(defn quit []
  "Gracefully quit - cancel all tasks."
  (for [t (asyncio.all-tasks)]
    :if (not (is t (asyncio.current-task)))
    (t.cancel)))
  

;; * handlers
;; ----------------------------------------------------------------------------

(defn accept-handler [buffer]
  "Dispatch to handler based on mode."
  (if input-field.command
    (command-input-handler buffer)
    (queue-input-handler buffer)))

(defn queue-input-handler [buffer]
  "Put the input in the queue."
  ;; the put is async, but called from sync function
  (when buffer.text
    (sync-await (.put state.input-queue
                      {"method" (if input-field.vdb
                                  "vdb"
                                  "chat")
                       "line" buffer.text}))
    ;; Explicitly require Ctrl-v to use RAG every time
    (setv input-field.vdb False))
  (mode-text)
  ;; TODO when image teed up, put the image-message in appropriately
  None)
  
(defn command-input-handler [buffer]
  "Send server RPC from the input buffer."
  (setv input-field.command False)
  (when buffer.text
    (let [arglist (shlex.split buffer.text)
          method (first arglist)
          ;; strip leading : from kws, so :key -> "key"
          ;; and mangle kw
          kwargs (dfor [k v] (pairwise (rest arglist))
                   (mangle (re.sub "^:" "" k)) v)]
      (assoc kwargs "chat" (:chat kwargs state.chat)) ; default to current chat
      (client-command method #** kwargs)))
  (mode-text)
  None)

(defn client-command [method #** kwargs]
  "Client commands are parsed here."
  (match method
    "load" (match (first kwargs)
             ;; TODO  image queueing up here
             ;;       format and send to input queue
             "chat" (set-chat :chat (:chat kwargs))
             "image" (raise NotImplementedError)
             "input" (input-text (slurp (:file kwargs)) :multiline True)
             "ws" 
             (let [fname (. (Path (:ws kwargs)) name)
                   text (.strip (slurp (:ws kwargs)))]
               (output-text f"{fname}\n\n")
               (output-text f"{text}\n\n")
               (sync-await (server-rpc "ws"
                             :provider state.provider
                             :fname fname
                             :text text
                             #** kwargs)))
             "profile" (do
                         (setv state.profile (:profile kwargs))
                         (title-text))
             "provider" (do
                          (setv state.provider (:provider kwargs))
                          (title-text))
             "prompt" (do
                        (setv state.prompt-name (:prompt kwargs))
                        (title-text)))
    _ (sync-await (server-rpc method :provider state.provider :prompt-name state.prompt-name #** kwargs))))


;; * setters, app state, text fields
;; ----------------------------------------------------------------------------

(defn set-input-prompt [n w]
  "Set the input field text prompt."
  (cond
    n "⋮ "
    input-field.command (ANSI f"{ansi.red}: ")
    input-field.multiline (ANSI f"{ansi.blue}> ")
    :else (ANSI f"{ansi.green}> ")))
  
(defn set-chat [* [chat None]]
  "Set the chat id."
  (when chat
    (setv state.chat chat)
    (setv input-field.text "")
    (setv output-field.text "")
    (sync-await (server-rpc "messages" :chat chat)))
  (title-text))

(clipman.init)

(setv kb (KeyBindings))

(setv status-field (Label :text "" :align WindowAlign.RIGHT :style "class:reverse"))
(setv title-field (Label :text "" :align WindowAlign.LEFT :style "class:reverse"))
(setv mode-field (Label :text ""
                        :width (fn [] (inc (len (to-plain-text mode-field.text))))
                        :align WindowAlign.RIGHT))
                        ;;:style "class:reverse"))
(setv output-field (TextArea :text ""
                             :wrap-lines True
                             :lexer (PygmentsLexer MarkdownLexer)
                             :read-only True))
(setv input-field (TextArea :multiline False
                            :height (Dimension :min 1 :max 3)
                            :wrap-lines True
                            :get-line-prefix set-input-prompt
                            :accept-handler accept-handler))
(setv input-field.multiline False)
(setv input-field.command False)
(setv input-field.vdb False)
(setv input-field.buffer.multiline (Condition (fn [] input-field.multiline)))
  

;; * the REPL app and state-setting functions
;; ----------------------------------------------------------------------------

(defclass REPLApp [Application]

  (defn __init__ [self] 
    "Set up the full-screen application, widgets, style and layout."

    (let [ptk-style (style-from-pygments-cls (get-style-by-name (:style state.cfg "friendly_grayscale")))
          padding (Window :width 2)]
      (setv container (HSplit [(VSplit [title-field status-field])
                               (VSplit [padding output-field padding]) 
                               ;(HorizontalLine) 
                               (VSplit [input-field mode-field])]))
      (title-text)
      (output-help)
      (.__init__ (super) :layout (Layout container :focused-element input-field)
                         :key-bindings kb
                         :style ptk-style
                         :mouse-support True
                         :full-screen True))))

(defn invalidate []
  "Redraw the app."
  (let [app (get-app-or-none)]
    (when app
      (.invalidate app))))
  

;; * printing functions
;; ----------------------------------------------------------------------------

(defn title-text []
  "Show the title."
  (setv title-field.text f"{state.profile} - {state.chat} ({state.token-count}+{state.workspace-count}) [{state.prompt-name}@{state.provider}] ")
  (invalidate))

(defn input-text [text * [multiline False] [command False]]
  "Set the input field text for editing."
  (let [term (get-terminal-size)]
    (setv input-field.command command)
    (setv input-field.multiline multiline)
    (if multiline
      (setv input-field.window.height (Dimension (// term.lines 2)))
      (setv input-field.window.height (Dimension :max 3 :min 1)))
    (setv input-field.document (Document :text (.strip text) :cursor-position 0))))

(defn output-text [output [replace False]]
  "Append (replace) output to output buffer text.
  Replaces text of output buffer.
  Moves cursor to the end."
  (let [new-text (if replace
                   output
                   (+ output-field.text output))
        tabbed-text (.replace new-text "\t" "    ")]
    (setv output-field.document (Document :text tabbed-text :cursor-position (len tabbed-text))))
  (invalidate))

(defn output-help []
  "Show the help text."
  (output-text (slurp (+ (os.path.dirname __file__) "/client-help.md"))))

(defn output-clear []
  "Nuke the output window."
  (setv output-field.text ""))

(defn status-text [text]
  "Set the status field text. Parses ANSI codes."
  (setv status-field.text (ANSI text))
  (invalidate))

(defn mode-text []
  "Set the mode field text. Parses ANSI codes."
  (let [modeline ""]
    (when input-field.command
      (setv modeline (.join " " [modeline f"{ansi.red}{ansi.rev}command{ansi.reset}"])))
    (when input-field.multiline
      (setv modeline (.join " " [modeline f"{ansi.blue}{ansi.rev}multiline{ansi.reset}"])))
    (when input-field.vdb
      (setv modeline (.join " " [modeline f"{ansi.cyan}{ansi.rev}vdb{ansi.reset}"])))
    (setv mode-field.text (ANSI modeline))
    (invalidate)))


;; * global key bindings
;;
;;   Take care: many common things like ctrl-m (return) or ctrl-h (backspace)
;;   interfere with normal operation.
;; ----------------------------------------------------------------------------

(defn [(kb.add "f1")] _ [event]
  "Pressing F1 will display some help text."
  (output-help))

(defn [(kb.add "c-q")] _ [event]
  "Pressing Ctrl-q  will cancel all tasks,
  including the REPLApp instance, and so
  exit the user interface."
  (event.app.exit)
  (quit))

;; TODO
(defn [(kb.add "c-c")] _ [event]
  "Abandon the current generation.")

#_(defn [(kb.add "c-p")] _ [event]
    "Set the active prompt"
    (with [(patch-stdout)] ; does it do anything?
      (setv state.prompt-name
            (sync-await
              (.run-async
                (input-dialog :title "Set prompt name" :text "Please type the name of your prompt"))))))

(defn :async [(kb.add "c-l")] _ [event]
  "Request list of messages.
  On receipt, replace the output with it."
  (await (server-rpc "messages" :chat state.chat)))
  ;(invalidate))

(defn [(kb.add "home")] _ [event]
  "Pressing HOME will scroll the output to the start."
  (event.app.layout.focus output-field.window)
  (setv output-field.document (Document :text output-field.text :cursor-position 0)))

(defn [(kb.add "end")] _ [event]
  "Pressing END will scroll the output to the end."
  (event.app.layout.focus output-field.window)
  (setv output-field.document (Document :text output-field.text :cursor-position (len output-field.text))))

(defn [(kb.add "pageup") (kb.add "c-b")] _ [event]
  "Pressing PGUP or Ctrl-b will scroll the output backwards."
  (event.app.layout.focus output-field.window)
  (scroll_page_up event))

(defn [(kb.add "pagedown") (kb.add "c-f")] _ [event]
  "Pressing PGDOWN or Ctrl-f will scroll the output forwards."
  (event.app.layout.focus output-field.window)
  (scroll_page_down event))
  
(defn [(kb.add "tab")] _ [event]
  "Pressing tab will toggle command mode."
  (event.app.layout.focus input-field)
  (let [term (get-terminal-size)]
    (if input-field.command
      (do ;; -> chat mode
        (setv input-field.command False)
        (mode-text))
      (do ;; -> command mode
        (setv input-field.command True)
        (mode-text)))))


;; * input-field key bindings
;; ----------------------------------------------------------------------------

(defn [(kb.add "s-tab" :filter (has-focus input-field))] _ [event]
  "Pressing shift-tab will toggle focus between input and output."
  (event.app.layout.focus output-field))

(defn [(kb.add "c-v" :filter (has-focus input-field))] _ [event]
  "Pressing Ctrl-v will toggle vdb RAG."
  (setv input-field.vdb (not input-field.vdb))
  (mode-text))

(defn [(kb.add "escape" "m" :filter input-field.buffer.multiline)] _ [event]
  "Pressing Escape-m (Alt-m) will toggle multi-line input."
  ;; -> single-line
  (setv input-field.window.height (Dimension :min 1 :max 3))
  (setv input-field.multiline False)
  (mode-text))

(defn [(kb.add "escape" "m" :filter (Condition (fn [] (not input-field.multiline))))] _ [event]
  "Pressing Escape-m (Alt-m) will toggle multi-line input."
  (let [term (get-terminal-size)]
    ;; -> multi-line
    (setv input-field.window.height (Dimension (// term.lines 2)))
    (setv input-field.multiline True)
    (mode-text)))


;; * output-field key bindings
;; ----------------------------------------------------------------------------

(defn [(kb.add "s-tab" :filter (has-focus output-field))] _ [event]
  "Pressing shift-tab will toggle focus between input and output."
  (event.app.layout.focus input-field))

(defn [(kb.add "y" :filter (has-focus output-field))] _ [event]
  "Pressing 'y' will send the output field selection to the clipboard."
  (when output-field.buffer.selection-state
    (clipman.copy (. (output-field.buffer.copy-selection) text))))


;; * instantiate the singleton
;; ----------------------------------------------------------------------------

(setv app (REPLApp))

