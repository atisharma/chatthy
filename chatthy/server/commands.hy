"
Implements server's RPC methods (commands)
"

(require hyrule.argmove [-> ->>])

(import itertools [batched])

(import hyjinx.lib [first last])
(import hyjinx.wire [wrap rpc rpcs])

(import inspect [signature])
(import re)
(import tabulate [tabulate])
(import time [time])

(import chatthy.server.completions [stream-completion truncate])
(import chatthy.embeddings [token-count])
(import chatthy.server.state [cfg
                              socket
                              get-chat set-chat delete-chat rename-chat list-chats
                              get-account set-account update-account])


;; * Client RPC message handling
;; -----------------------------------------------------------------------------

(defn :async client-rpc [sid method #** kwargs]
  "Remotely call a client method with kwargs that a client expects.
  Wraps and sends the message to the client."
  (let [msg {"method" method #** kwargs}]
    (await (.send-multipart socket [sid (wrap msg)]))))

;; * The server's RPC methods, offered to the client, registered to hyjinx.wire
;; -----------------------------------------------------------------------------

(defn :async [rpc] status [* sid #** kwargs]
  ;; no docstring so it doesn't advertise to clients
  ;; regular status update
  (await (client-rpc sid "status" :result f"idle")))

(defn :async [rpc] echo [* sid result #** kwargs]
  ;; no docstring so it doesn't advertise to clients
  ;; send a chat message to the client
  (await (client-rpc sid
                     "echo"
                     :result {"role" "server" "content" result})))

(defn :async [rpc] messages [* sid username chat #** kwargs]
  ;; no docstring so it doesn't advertise to clients
  ;;Send all the user's messages.
  (await (client-rpc sid
                     "messages"
                     :result (get-chat username chat))))

(defn :async [rpc] account [* sid username #** kwargs]
  "Show account details."
  (let [d-account (get-account username)]
    (.pop d-account "prompts" None)
    (await (echo :sid sid
                 :result (+ f"account {username}\n\n"
                            (tabulate (.items d-account)
                                      :maxcolwidths [None 60]))))))

(defn :async [rpc] prompts [* sid username [name None] [prompt None] #** kwargs]
  "Gets/sets a named system prompt for a user. With no args, list them."
  (let [prompts (:prompts (get-account username) {})]
    (if (and name prompt)
      (update-account username :prompts (| prompts {name prompt}))
      (await (echo :sid sid
                   :result (+ "prompts\n\n"
                              (tabulate (list (.items prompts))
                                        :headers ["name" "prompt text"]
                                        :maxcolwidths [None 60])))))))

(defn :async [rpc] chats [* sid username #** kwargs]
  "List the user's saved chats."
  (await (client-rpc sid
                     "chats"
                     :result (list-chats username))))

(defn :async [rpc] rename [* sid username chat to #** kwargs]
  "Rename the user's chat."
  (rename-chat username chat to))

(defn :async [rpc] providers [* sid #** kwargs]
  "List the providers available to clients."
  (await (echo :sid sid
               :result (.join "\n"
                         ["providers available:\n"
                          #* (sorted (list (.keys (:providers cfg))))]))))

(defn :async [rpc] commands [* sid #** kwargs]
  "List the commands advertised to clients."
  (await (echo :sid sid
               :result (+ "commands available:\n\n"
                          (tabulate
                            (sorted
                              (lfor [k v] (.items rpcs)
                                :if v.__doc__
                                (let [sig (->> (signature v)
                                               (str)
                                               (re.sub r"sid, " "")
                                               (re.sub r", \*\*kwargs" "")
                                               (re.sub r"\(\*" "")
                                               (re.sub r"\)" "")
                                               (re.sub r", " " :")
                                               (re.sub r" :username" "")
                                               (re.sub r"=[\w]+" ""))]
                                  #( k sig v.__doc__))))
                            :headers ["command" "kwargs" "doc"])))))

(defn :async [rpc] destroy [* sid username chat]
  "Destroy the whole chat (default current chat)."
  (delete-chat username chat)
  (await (messages :sid sid :username username :chat chat))
  (await (client-rpc sid "info" :result "Chat destroyed.")))

(defn :async [rpc] undo [* sid username chat #** kwargs]
  "Destroy the last message pair (default current chat)."
  (let [messages (cut (get-chat username chat) -2)]
    (set-chat messages username chat))
  (await (messages :sid sid :username username :chat chat)))

(defn :async [rpc] chat [* sid username chat prompt-name line provider #** kwargs]
  ;; no docstring so it doesn't advertise to clients
  ;; Send the streamed reply in batched chunks.
  (let [reply ""
        chunk ""
        prompts (:prompts (get-account username))
        system-prompt (.get prompts prompt-name (:system cfg))
        system-msg {"role" "system" "content" system-prompt}
        usr-msg {"role" "user" "content" line "timestamp" (time)}
        all-messages (get-chat username chat)
        [messages dropped] (truncate all-messages :space (+ (:max-tokens cfg 600) (token-count system-prompt)))]
    (for [chunk (map (fn [xs] (.join "" xs))
                     (batched (stream-completion provider [system-msg #* messages usr-msg] #** kwargs)
                              (:batch cfg 2)))]
      (+= reply chunk)
      (await (client-rpc sid "status" :result "streaming"))
      (await (client-rpc sid "chunk" :result chunk)))
    (await (client-rpc sid "chunk" :result "\n\n"))
    (.append all-messages usr-msg)
    (.append all-messages {"role" "assistant" "content" reply "timestamp" (time)})
    (set-chat all-messages username chat))
  (await (client-rpc sid "status" :result "ready")))

