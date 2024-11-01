"
Implements server side of async DEALER-ROUTER pattern.
"

(require hyrule.argmove [-> ->>])
(require hyrule [defmain])

(import hyrule [flatten])
(import functools [partial])
(import itertools [batched])
(import toolz.recipes [partitionby])

(import hyjinx [crypto])
(import hyjinx.lib [first last config hash-id])
(import hyjinx.wire [wrap unwrap rpc rpcs handoff])

(import asyncio)
(import inspect [signature])
(import json)
(import sys)
(import time [time])
(import traceback [format-exception])
(import zmq)
(import zmq.asyncio)

(import chatthy.server.completions [stream-completion])
(import chatthy.server.state [cfg
                              get-chat set-chat delete-chat list-chats
                              get-account set-account update-account
                              get-pubkey])

(import asyncio [CancelledError])


(setv context (zmq.asyncio.Context))
(setv socket (.socket context zmq.ROUTER))

(.bind socket (:listen cfg))

;; * The server's RPC methods, offered to the client
;; -----------------------------------------------------------------------------

(defn :async [rpc] status [* sid #** kwargs]
  ;; regular status update
  (await (client-rpc sid "status" :result f"idle")))

(defn :async [rpc] echo [* sid result #** kwargs]
  ;; send a chat message to the client
  (await (client-rpc sid
                     "echo"
                     :result {"role" "server" "content" result})))

(defn :async [rpc] messages [* sid username chat-id #** kwargs]
  ;;Send all the user's messages.
  (await (client-rpc sid
                     "messages"
                     :result (get-chat username chat-id))))

(defn :async [rpc] account [* sid username #** kwargs]
  "Show account details."
  (await (echo :sid sid
               :result (+ f"\naccount\n{username}\n"
                          (.join "\n"
                            (lfor [k v] (.items (get-account username))
                              f"{k}: {v}"))))))

(defn :async [rpc] system [* sid username [prompt None] #** kwargs]
  "Sets the system prompt for that user."
  (when prompt
    (update-account username :system prompt))
  (await (echo :sid sid
               :result (+ "prompt\n\n"
                          (:system (get-account username) (:system cfg))))))

(defn :async [rpc] chats [* sid username #** kwargs]
  "List the user's saved chats."
  (await (client-rpc sid
                     "chats"
                     :result (list-chats username))))

(defn :async [rpc] providers [* sid #** kwargs]
  "List the providers available to clients."
  (await (echo :sid sid
               :result (+ "providers available:\n\n"
                          (.join "\n"
                            (sorted (list (.keys (:providers cfg)))))))))

(defn :async [rpc] commands [* sid #** kwargs]
  "List the commands advertised to clients."
  (await (echo :sid sid
               :result (+ "commands available:\n\n"
                          (.join "\n"
                            (sorted
                              (lfor [k v] (.items rpcs)
                                :if v.__doc__
                                (let [sig (-> (signature v)
                                              (str)
                                              (.replace "sid, " "")
                                              (.replace ", **kwargs" "")
                                              (.replace "(*" "")
                                              (.replace ")" "")
                                              (.replace ", " " :"))]
                                  f"{k} {sig} -- {v.__doc__}"))))))))

(defn :async [rpc] destroy [* sid username chat-id]
  "Destroy the whole chat."
  (delete-chat username chat-id)
  (await (messages :sid sid :username username :chat-id chat-id))
  (await (client-rpc sid "info" :result "Chat destroyed.")))

(defn :async [rpc] undo [* sid username chat-id #** kwargs]
  "Destroy the last message pair."
  (let [messages (cut (get-chat username chat-id) -2)]
    (set-chat messages username chat-id))
  (await (messages :sid sid :username username :chat-id chat-id)))

(defn :async [rpc] chat [* sid username chat-id line provider #** kwargs]
  ;; Send the streamed reply in batched chunks.
  (let [reply ""
        chunk ""
        system-msg {"role" "system" "content" (:system (get-account username) (:system cfg))}
        usr-msg {"role" "user" "content" line "timestamp" (time)}
        messages (get-chat username chat-id)]
    (for [chunk (map (fn [xs] (.join "" xs))
                     (batched (stream-completion provider [system-msg #* messages usr-msg] #** kwargs)
                              (:batch cfg 2)))]
      (+= reply chunk)
      (await (client-rpc sid "status" :result "streaming"))
      (await (client-rpc sid "chunk" :result chunk)))
    (await (client-rpc sid "chunk" :result "\n"))
    (.append messages usr-msg)
    (.append messages {"role" "assistant" "content" reply "timestamp" (time)})
    (set-chat messages username chat-id))
  (await (client-rpc sid "status" :result "ready")))

;; * RPC message handling stuff
;; -----------------------------------------------------------------------------

(defn :async client-rpc [sid method #** kwargs]
  "Remotely call a client method with kwargs that the client expects.
  Wraps and sends the message to the client."
  (let [msg {"method" method #** kwargs}]
    (await (.send-multipart socket [sid (wrap msg)]))))

;; TODO use hyjinx.crypto.is-recent instead
(defn is-stale [client-time [threshold 60]]
  "Is client's message time outside threshold (seconds) of server time, or bad?"
  (try
    (let [ct (float client-time)
          diff (abs (- ct (time)))]
      (> diff threshold))
    (except [ValueError]
      True)))

(defn :async handle-msgs []
  "Verify and handoff incoming messages."
  (while True
    (try
      (let [frames (await (.recv-multipart socket))
            [sid zmsg] frames]
        (try
          (let [msg (unwrap zmsg)
                payload (:payload msg)
                username (:username (:payload msg) "")
                pub-key (get-pubkey username (:public-key msg None)) ;; use the stored public key if it exists
                signature (:signature msg "")
                client-time (:sender-time msg Inf)
                expected-hash (hash-id (+ (str (:sender-time msg))
                                          (str payload)))]

            (cond
              (is-stale client-time)
              (await (client-rpc sid "status" :result f"'{(:method payload)}' request stale, server may be busy or your clock is wrong."))

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
        (print (.join "\n" format-exception e))))))

;; * cli stuff
;; -----------------------------------------------------------------------------

(defn :async main []
  ;; default to 10 concurrent tasks
  (let [tasks (lfor i (range (:tasks cfg 10))
                (asyncio.create-task (handle-msgs)))]
    (await (asyncio.wait tasks))))

(defn run []
  "Run the input and output tasks."
  (sys.exit
    (try
      (asyncio.run (main))
      (except [e [KeyboardInterrupt CancelledError]]))))

(defmain []
  "Start the server."
  (run))
  
