"
The client's offered RPCs.
"

(require hyrule.argmove [-> ->>]) 

(import hyjinx [config first second last])
(import hyjinx.wire [rpc])

(import os)
(import re)
(import json)
(import atexit)

(import shutil [get-terminal-size])
(import tabulate [tabulate])
(import time [time])
(import traceback [format-exception])

(import chatthy.client [state])
(import chatthy.embeddings [token-count])
(import chatthy.client.ptk-app [app ; this is imported by repl.hy
                                sync-await
                                output-clear
                                input-text
                                output-text
                                status-text
                                title-text])


;; TODO consider tabulated over tabulate

;; * status
;; -----------------------------------------------------------------------------

(defn update-status []
  "Check the age of the last status message and show."
  (try
    (let [age (- (time) (:server-time state.server-status 0))]
      (status-text (if (> age 15)
                     f"no response from server ❌"
                     (:result state.server-status))))
    (except [e [BaseException]]
      (status-text f"confusing status: {(str status)} {(str e)} ❌"))))


;; * printers, input hook
;; -----------------------------------------------------------------------------

;; TODO manage image messages
(defn quote-lines [line [prefix ["> " "… "]]]
  "Quote a single-line string with '> ' (first prefix).
  Quote a multi-line string with ellipsis and indent (second prefix)."
  (+ (first prefix)
     (if (.count line "\n")
       (.join f"\n{(second prefix)}"
         (.split line "\n"))
       line)))

(defn print-input [line]
  "Print a line of input."
  (sync-await (echo :result {"role" "user" "content" line})))

(defn print-exception [exception [s ""]]
  (output-text f"# ❌Client exception\n```py3tb\n")
  (output-text (.join "\n" (format-exception exception)))
  (output-text f"\n```\n{s}\n\n"))


;; * RPC calls -- all receive payload
;; -----------------------------------------------------------------------------

(defn :async [rpc] status [#** kwargs]
  "Set the status and update the status bar."
  (setv state.server-status {#** state.server-status
                             #** kwargs})
  (update-status))

(defn :async [rpc] error [* result #** kwargs]
  (output-text f"⚠️ {(str result)}\n\n"))

(defn :async [rpc] info [* result #** kwargs]
  (output-text f"ℹ️ {(str result)}\n\n"))

(defn :async [rpc] echo [* result #** kwargs]
  "Format and print a message with role to the screen."
  ;; It would be nice to indent > multiline user input
  ;; but we don't know where it will be wrapped.
  (when result
    (let [text (match (:role result)
                 "assistant" (:content result)
                 "user" (quote-lines (:content result))
                 "system" (+ f"❕ System " (:content result))
                 "server" (+ f"❕ Server " (:content result))
                 _ (+ f"{(:role msg)}: " (:content result)))]
      (output-text
        (+ text "\n\n")))))

(defn :async [rpc] chunk [* result chat #** kwargs]
  "Print a chunk of a stream."
  (when (= chat state.chat)
    (output-text result)))

(defn :async [rpc] messages [* workspace chat #** kwargs]
  "Clear the text and print all the messages."
  (output-clear)
  (setv state.token-count (token-count chat))
  (setv state.workspace-count (token-count workspace))
  (title-text)
  (output-text "\n")
  (for [m workspace]
    (await (echo :result m)))
  (when workspace
    (output-text (* "-" 80))
    (output-text "\n\n"))
  (for [m chat]
    (await (echo :result m))))

(defn :async [rpc] chats [* result #** kwargs]
  "Print the saved chats, which are received as a list."
  (output-text f"# ❕Saved chats\n")
  (if result
    (for [c result]
      (output-text f"- {c}\n"))
    (output-text "  (no chats)"))
  (output-text "\n\n"))

(defn :async [rpc] commands [* result #** kwargs]
  "Display the list of commands advertised by the server."
  (output-text (+ "# ❕Server commands available:\n\n"
                  (tabulate (sorted result :key :command)
                    :headers "keys"
                    :maxcolwidths [12 20 (- (. (get-terminal-size :fallback [80 20]) columns) 37)])
                  "\n\n")))

(defn :async [rpc] prompts [* result #** kwargs]
  "Display the list of prompts known to the server."
  (output-text (+ "# ❕Prompts available:\n\n"
                  (tabulate (sorted result :key :prompt)
                    :headers "keys"
                    :maxcolwidths [12 (- (. (get-terminal-size :fallback [80 20]) columns) 17)])
                  "\n\n")))

(defn :async [rpc] providers [* result #** kwargs]
  "Display the list of providers known to the server."
  (output-text (+ "# ❕Providers available:\n\n"
                  (.join "\n" result)
                  "\n\n")))

(defn :async [rpc] workspace [* result #** kwargs]
  "Print the files in the current workspace, which are received as a list of dicts,
  `{name length}`."
  (setv state.workspace-count 0)
  (output-text f"# ❕Files in current workspace (✓ active, x ignored)\n")
  (if result
    (for [wsf result]
      (let [ignored-str (if (:ignored wsf) "x" "✓")
            length (:length wsf)
            name (:name wsf)]
        (output-text f"- {ignored-str} {name} ({length})\n")
        (+= state.workspace-count length)))
    (output-text "  (no files)"))
  (output-text "\n\n"))

(defn :async [rpc] set-prompt [* prompt name #** kwargs]
  "Set the input field text to the payload."
  (input-text
    f"prompts :name {name} :prompt \"{prompt}\""
    :command True))

