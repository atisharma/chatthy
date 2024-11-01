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
(import chatthy.client.ptk-app [app
                                sync-await
                                output-clear
                                output-text
                                status-text
                                title-text])
(import chatthy.embeddings [token-count])


;; * status
;; -----------------------------------------------------------------------------

(defn show-status []
  "Check the age of the last status message and show."
  (try
    (let [age (- (time) (:server-time _status 0))]
      (status-text (if (> age 15)
                     f"NO REPLY"
                     (:result _status))))
    (except [e [BaseException]]
      (status-text f"CONFUSING STATUS: {(str status)} {(str e)}"))))

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
  (show-status))

(defn :async [rpc] error [* result #** kwargs]
  (output-text f"## Error\n{(str result)}\n\n"))

(defn :async [rpc] info [* result #** kwargs]
  (output-text f"Info: {(str result)}\n\n"))

;; TODO indent > multiline user input
(defn :async [rpc] echo [* result #** kwargs]
  "Format and print a message with role to the screen."
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

(defn :async [rpc] messages [* result #** kwargs]
  "Clear the text and print all the messages."
  (output-clear)
  (setv state.token-count (token-count result))
  (title-text)
  (for [m result]
    (await (echo :result m))))

(defn :async [rpc] chats [* result #** kwargs]
  "Print the saved chats, which are received as a list."
  (output-text f"## Saved chats\n")
  (for [c result]
    (output-text f"- {c}\n"))
  (output-text "\n\n"))

