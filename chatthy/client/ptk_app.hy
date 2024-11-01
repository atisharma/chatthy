"
Application for simple chat REPL.
"

;; TODO cut, paste
;; TODO Ctrl-C cancel generation

(require hyrule [defmain])

(import hyrule [assoc])
(import hyjinx.lib [first rest slurp])
(import itertools [pairwise])

(import asyncio)
(import re)
(import os)
(import pansi [ansi])
(import shutil [get-terminal-size])
(import shlex)

(import prompt-toolkit [ANSI])
(import prompt-toolkit.application [Application get-app-or-none])
(import prompt_toolkit.layout [WindowAlign])
(import prompt_toolkit.layout.dimension [Dimension])
(import prompt-toolkit.document [Document])
(import prompt-toolkit.filters [Condition is-multiline])
;(import prompt-toolkit.formatted-text [FormattedText])
(import prompt-toolkit.key-binding [KeyBindings])
(import prompt_toolkit.key_binding.bindings.page_navigation [scroll_page_up scroll_page_down])
(import prompt-toolkit.layout.containers [HSplit VSplit Window])
(import prompt-toolkit.layout.layout [Layout])
(import prompt-toolkit.patch-stdout [patch-stdout])
;(import prompt-toolkit.styles [Style])
(import prompt-toolkit.widgets [Label HorizontalLine SearchToolbar TextArea])

(import prompt-toolkit.styles.pygments [style-from-pygments-cls])
(import prompt-toolkit.lexers [PygmentsLexer])
(import pygments.lexers [MarkdownLexer])
(import pygments.styles [get-style-by-name])

(import chatthy.client [state])
(import chatthy.client.client [server-rpc])


;; TODO sort what should be in here and in interface.hy

;; * general functions
;; ----------------------------------------------------------------------------

(defn sync-await [coroutine]
  "Call a coroutine from inside a synchronous function,
  itself called from inside the async event loop."
  (asyncio.run_coroutine_threadsafe
    coroutine
    (asyncio.get-event-loop)))
  
(defn accept-handler [buffer]
  "Dispatch to handler based on mode."
  (if input-field.command
    (command-input-handler buffer)
    (queue-input-handler buffer)))

(defn queue-input-handler [buffer]
  "Put the input in the queue."
  ;; the put is async, but called from sync function
  (when buffer.text
    (sync-await (.put state.input-queue buffer.text)))
  None)
  
(defn command-input-handler [buffer]
  "Send server RPC from the input buffer."
  (setv input-field.command False)
  (mode-text "")
  (when buffer.text
    (let [arglist (shlex.split buffer.text)
          method (first arglist)
          ;; strip leading : from kws, so :key -> "key"
          kwargs (dfor [k v] (pairwise (rest arglist))
                   (re.sub "^:" "" k) v)]
      (assoc kwargs "chat_id" (:chat-id kwargs state.chat-id)) ; default to current chat
      (match method
        "switch" (sync-await (set-chat-id :chat-id (:chat-id kwargs)))
        _ (sync-await (server-rpc method #** kwargs)))))
  None)
  
(defn ansi-strip [s]
  "Strip ANSI control codes."
  (re.sub r"\033\[[0-9;]*m" "" s))

(defn quit []
  "Gracefully quit - cancel all tasks."
  (for [t (asyncio.all-tasks)]
    :if (not (is t (asyncio.current-task)))
    (t.cancel)))

;; * app state, text fields
;; ----------------------------------------------------------------------------

(defn set-prompt [n w]
  "Set the input field text prompt."
  (cond
    n "⋮ "
    input-field.command (ANSI f"{ansi.red}: ")
    :else (ANSI f"{ansi.green}> ")))
  
(setv kb (KeyBindings))

(setv status-field (Label :text "" :style "class:reverse"))
(setv chat-id-field (Label :text "" :align WindowAlign.CENTER :style "class:reverse"))
(setv mode-field (Label :text "" :align WindowAlign.RIGHT :style "class:reverse"))
(setv output-field (TextArea :text ""
                             :wrap-lines True
                             :lexer (PygmentsLexer MarkdownLexer)))

(setv input-field (TextArea :multiline False
                            :height (Dimension :min 1 :max 3)
                            :wrap-lines True
                            :get-line-prefix set-prompt
                            :accept-handler accept-handler))
(setv input-field.multiline False)
(setv input-field.command False)
(setv input-field.buffer.multiline (Condition (fn [] input-field.multiline)))
  
;; * the REPL app and functions
;; ----------------------------------------------------------------------------

(defclass REPLApp [Application]

  (defn __init__ [self [banner ""]]
    "Set up the full-screen application, widgets, style and layout."

    (let [ptk-style (style-from-pygments-cls (get-style-by-name (:style state.cfg "friendly_grayscale")))]
      (setv output-field.text banner)
      (setv container (HSplit [
                               (VSplit [status-field chat-id-field mode-field])
                               ;(HorizontalLine) 
                               output-field
                               ;(HorizontalLine) 
                               input-field]))
      (setv chat-id-field.text f"{state.username} [{state.chat-id}]")
      (output-help)
      (.__init__ (super) :layout (Layout container :focused-element input-field)
                         :key-bindings kb
                         :style ptk-style
                         :mouse-support True
                         :full-screen True)))

  (defn output-text [self output [replace False]]
    "Append output to output buffer text.
    Replaces text of output buffer.
    Moves cursor to the end."
    (output-text (.replace output "\t" "    ") :replace replace))

  (defn status-text [self text]
    "Set the status field text. Parses ANSI codes."
    (status-text text))

  (defn mode-text [self text]
    "Set the mode field text. Parses ANSI codes."
    (mode-text text))

  (defn :async set-chat-id [self * chat-id]
    "Set the chat id to the contents of the input field."
    (await (set-chat-id :chat-id chat-id))))

(defn :async set-chat-id [* [chat-id None]]
  "Set the chat id."
  (when chat-id
    (setv state.chat-id chat-id)
    (setv chat-id-field.text f"{state.username} [{chat-id}]")
    (setv input-field.text "")
    (setv output-field.text "")
    (await (server-rpc "messages" :chat-id chat-id))))

(defn output-clear []
  "Nuke the output window."
  (setv output-field.text ""))

;; * printing functions
;; ----------------------------------------------------------------------------

(defn output-text [output [replace False]]
  "Append output to output buffer text.
  Replaces text of output buffer.
  Moves cursor to the end."
  (let [new-text (if replace
                   output
                   (+ output-field.text output))]
    (setv output-field.document (Document :text new-text :cursor-position (len new-text))))
  (invalidate))

(defn status-text [text]
  "Set the status field text. Parses ANSI codes."
  (setv status-field.text (ANSI text))
  (invalidate))

(defn mode-text [text]
  "Set the mode field text. Parses ANSI codes."
  (setv mode-field.text (ANSI text))
  (invalidate))

(defn invalidate []
  "Redraw the app."
  (let [app (get-app-or-none)]
    (when app
      (.invalidate app))))
  
(defn output-help []
  "Show the help text."
  (output-text (slurp (or (+ (os.path.dirname __file__) "/client-help.md")))))

;; * key bindings
;;   Take care: many common things like ctrl-m (return) or ctrl-h (backspace)
;;   interfere with normal operation.
;; ----------------------------------------------------------------------------

;; TODO send general server-rpc commands

(defn [(kb.add "c-q")] _ [event]
  "Pressing Ctrl-q  will cancel all tasks,
  including the REPLApp instance, and so
  exit the user interface."
  (event.app.exit)
  (quit))

;; TODO
(defn [(kb.add "c-c")] _ [event]
  "Abandon the current generation.")

(defn :async [(kb.add "c-r")] _ [event]
  "Request list of messages.
  On receipt, replace the output with it."
  (await (server-rpc "messages" :chat-id state.chat-id)))

(defn [(kb.add "s-tab")] _ [event]
  "Pressing Shift-tab will toggle server command mode."
  (let [term (get-terminal-size)]
    (if input-field.command
      (do ;; -> chat mode
        (mode-text "")
        (setv input-field.command False))
      (do ;; -> command mode
        (mode-text "command")
        (setv input-field.command True)))))

;; TODO home, end
(defn [(kb.add "pageup") (kb.add "c-b")] _ [event]
  "Pressing PGUP or Ctrl-b will scroll the output backwards."
  (event.app.layout.focus output-field.window)
  (scroll_page_up event)
  (event.app.layout.focus input-field))

(defn [(kb.add "pagedown") (kb.add "c-f")] _ [event]
  "Pressing PGDOWN or Ctrl-f will scroll the output forwards."
  (event.app.layout.focus output-field.window)
  (scroll_page_down event)
  (event.app.layout.focus input-field))
  
(defn [(kb.add "c-l")] _ [event]
  "Pressing Ctrl-l will toggle multi-line input."
  (let [term (get-terminal-size)]
    (if input-field.multiline
      (do ;; -> single-line
        (mode-text "")
        (setv input-field.window.height (Dimension :min 1 :max 3))
        (setv input-field.multiline False))
      (do ;; -> multi-line
        (mode-text "multiline")
        (setv input-field.window.height (Dimension (// term.lines 2)))
        (setv input-field.multiline True)))))

(defn [(kb.add "f1")] _ [event]
  "Pressing F1 will display some help text."
  (output-help))

;; * instantiate the singleton
;; ----------------------------------------------------------------------------

(setv app (REPLApp :banner "
  ┏┓┓     ┓   
  ┃ ┣┓┏┓╋╋┣┓┓┏
  ┗┛┛┗┗┻┗┗┛┗┗┫
             ┛"))

