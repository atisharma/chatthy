"
Implements server side of async DEALER-ROUTER pattern.
"

(require hyrule.argmove [-> ->>])
(require hyrule [defmain])

(import hyjinx [crypto])
(import hyjinx.lib [hash-id])
(import hyjinx.wire [unwrap handoff])

(import asyncio)
(import re)
(import sys)
(import traceback [format-exception])

(import fvdb [similar])
(import chatthy.server.state [cfg socket get-pubkey])
(import chatthy.server.commands [client-rpc]) ; this also registers the RPC commands

(import asyncio [CancelledError])


;; * Client RPC message handling
;; -----------------------------------------------------------------------------

(defn :async handle-msgs []
  "Verify and handoff incoming messages from a client."
  (while True
    (try
      (let [frames (await (.recv-multipart socket))
            [sid zmsg] frames]
        (try
          (let [msg (unwrap zmsg)
                payload (:payload msg)
                profile (:profile (:payload msg) "")
                pub-key (get-pubkey profile (:public-key msg None)) ;; use the stored public key if it exists
                signature (:signature msg "")
                client-time (:sender-time msg Inf)
                expected-hash (hash-id (+ (str (:sender-time msg))
                                          (str payload)))]

            (cond
              (not (crypto.is-recent client-time))
              (await (client-rpc sid "status"
                       :result f"'{(:method payload)}' request stale, server may be busy or your clock is wrong."))

              (crypto.verify pub-key signature expected-hash)
              (await (handoff {"sid" sid #** payload}))

              (not (crypto.verify pub-key signature expected-hash))
              (await (client-rpc sid "error" :result f"Message signing failed."))

              :else
              (await (client-rpc sid "error" :result f"Unknown error."))))

          (except [e [Exception]]
            (print (.join "\n" (format-exception e)))
            (await (client-rpc sid "error" :result f"Server exception:\n{(str e)}")))))
      (except [e [Exception]]
        (print (.join "\n" (format-exception e)))))))

;; * cli stuff
;; -----------------------------------------------------------------------------

(defn :async main []
  "Start the server, bind to the socket.
  Run the input and output tasks."
  (.bind socket (:listen cfg))
  ;; default to 10 concurrent tasks
  (let [tasks (lfor i (range (:tasks cfg 10))
                (asyncio.create-task (handle-msgs)))]
    (await (asyncio.wait tasks))))

(defn run []
  (sys.exit
    (try
      (asyncio.run (main))
      (except [e [KeyboardInterrupt CancelledError]]))))

(defmain []
  (run))
  
