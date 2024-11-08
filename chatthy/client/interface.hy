"
The client's offered RPCs.
"

(require hyrule.argmove [-> ->>]) 

(import hyjinx [config first])
(import hyjinx.wire [rpc])

(import os)
(import re)
(import json)
(import atexit)

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


;; * status
;; -----------------------------------------------------------------------------

(defn update-status []
  "Check the age of the last status message and show."
  (try
    (let [age (- (time) (:server-time _status 0))]
      (status-text (if (> age 15)
                     f"no response from server"
                     (:result _status))))
    (except [e [BaseException]]
      (status-text f"confusing status: {(str status)} {(str e)}"))))

(setv _status {"result" "Connecting"})


;; * printers, input hook
;; -----------------------------------------------------------------------------

(defn print-input [line]
  "Print a line of input."
  (sync-await (echo :result {"role" "user" "content" f"{line}"})))

(defn print-exception [exception [s ""]]
  (output-text f"## Client exception\n```py3tb\n")
  (output-text (.join "\n" (format-exception exception)))
  (output-text f"\n```\n{s}\n\n"))


;; * RPC calls -- all receive payload
;; -----------------------------------------------------------------------------

(defn :async [rpc] status [#** kwargs]
  "Set the status and update the status bar."
  (global _status)
  (setv _status {#** _status
                 #** kwargs})
  (update-status))

(defn :async [rpc] error [* result #** kwargs]
  (output-text f"## Error\n{(str result)}\n\n"))

(defn :async [rpc] info [* result #** kwargs]
  (output-text f"Info: {(str result)}\n\n"))

(defn :async [rpc] echo [* result #** kwargs]
  "Format and print a message with role to the screen."
  ;; It would be nice to indent > multiline user input
  ;; but we don't know where it will be wrapped.
  (when result
    (let [role-prompt (match (:role result)
                        "assistant" ""
                        "user" "> "
                        "system" f"## System "
                        "server" f"## Server "
                        _ f"{(:role msg)}: ")]
      (output-text
        (+ role-prompt (:content result) "\n\n")))))

(defn :async [rpc] chunk [* result #** kwargs]
  "Print a chunk of a stream."
  (output-text result))

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
  (output-text f"## Saved chats\n")
  (if result
    (for [c result]
      (output-text f"- {c}\n"))
    (output-text "  (no chats)"))
  (output-text "\n\n"))

(defn :async [rpc] workspace [* result #** kwargs]
  "Print the files in the current workspace, which are received as a list of dicts,
  `{name length}`."
  (setv state.workspace-count 0)
  (output-text f"## Files in current workspace\n")
  (if result
    (for [c result]
      (output-text f"- {(:name c)} ({(:length c)})\n")
      (+= state.workspace-count (:length c)))
    (output-text "  (no files)"))
  (output-text "\n\n"))

(defn :async [rpc] set-prompt [* prompt name #** kwargs]
  "Set the input field text to the payload."
  (input-text
    f"prompts :name {name} :prompt \"{prompt}\""
    :command True))

