"
The main REPL where we read output and issue commands.
"

(require hyrule [-> ->>
                 defmain
                 unless])

(import hyjinx [config])

(import asyncio)
(import asyncio [CancelledError])
(import json)
(import sys)

(import chatthy.client [state])
(import chatthy.client.client [send recv handoff server-rpc])
(import chatthy.client.interface [app
                                  status echo
                                  update-status
                                  print-input
                                  print-exception])

;; * The REPL processes
;; -----------------------------------------------------------------------------

(defn :async get-server-status [[delay 10]]
  "Loop to request status from the server."
  (while True
    (try
      (await (server-rpc "status"))
      (await (asyncio.sleep delay))
      (except [e [Exception]]
        (print-exception e)))))

(defn :async show-server-status [[delay 1]]
  "Loop to display most recent status from the server."
  (while True
    (try
      (update-status)
      (await (asyncio.sleep delay))
      (except [e [Exception]]
        (print-exception e)))))

(defn :async repl-output []
  "Output loop to receive the server's reply."
  (while True
    (let [reply (await (recv))]
      (try
        (when reply
          (await (handoff reply)))
        (except [e [BaseException]]
          (print-exception e f"\n## Error handling message\n{(json.dumps reply :indent 4)}"))))))

(defn :async repl-input []
  "Takes input, then passes it to the appropriate action."
  (while True
    (try
      (let [action (await (.get state.input-queue))]
        (when action
          (match (:method action None)
            "chat"
            (await (server-rpc :method "chat"
                               :chat state.chat
                               :line (:line action)
                               :prompt-name state.prompt-name 
                               :provider state.provider))
            "vdb"
            (await (server-rpc :method "vdb"
                               :chat state.chat
                               :query (:line action)
                               :prompt-name state.prompt-name 
                               :provider state.provider)))))
      (except [e [Exception]]
        (print-exception e)))))

(defn :async main-loop []
  (await (asyncio.gather (repl-input)
                         (repl-output)
                         (get-server-status)
                         (show-server-status)
                         (app.run-async))))

(defn run []
  "Run the input and output tasks."
  (sys.exit
    (try
      (asyncio.run (main-loop))
      (except [CancelledError]))))

(defmain []
  "Run the input and output tasks."
  (run))
