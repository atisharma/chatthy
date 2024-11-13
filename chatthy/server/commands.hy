"
Implements server's RPC methods (commands)
"

(require hyrule.argmove [-> ->>])

(import hyjinx.lib [first last short-id])
(import hyjinx.wire [wrap rpc rpcs])

(import inspect [signature])
(import re)
(import tabulate [tabulate])
(import time [time])

(import trag [retrieve])
(import chatthy [__version__])
(import chatthy.server.completions [stream-completion truncate])
(import chatthy.embeddings [token-count])
(import chatthy.server.rag [vdb-extracts vdb-info
                            extract-output
                            workspace-messages])
(import chatthy.server.state [cfg
                              socket
                              get-prompts get-prompt update-prompt
                              get-chat set-chat delete-chat copy-chat rename-chat list-chats
                              get-ws write-ws drop-ws rename-ws list-ws
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
  (await (client-rpc sid "status" :result f"v{__version__} ✅")))

(defn :async [rpc] echo [* sid result #** kwargs]
  ;; no docstring so it doesn't advertise to clients
  ;; send a chat message to the client
  (await (client-rpc sid
                     "echo"
                     :result {"role" "server" "content" result})))

(defn :async [rpc] account [* sid profile #** kwargs]
  "Show account details."
  ;; TODO return dict, not text
  (let [d-account (get-account profile)]
    (.pop d-account "prompts" None)
    (await (echo :sid sid
                 :result (+ f"account {profile}\n\n"
                            (tabulate (.items d-account)
                                      :maxcolwidths [None 60]))))))

(defn :async [rpc] prompts [* sid profile [name None] [prompt None] #** kwargs]
  "Gets/sets a named system prompt for a user. With just name given, edit it. With no kwargs, list them."
  (let [prompts (get-prompts profile)]
    (cond
      ;; client has specified both prompt name and text, so set the prompt
      (and name prompt)
      (update-prompt profile prompt-name prompt)

      ;; client hasn't specified prompt text, so just get and return
      (and name)
      (await (client-rpc :sid sid
                         :method "set_prompt"
                         :name name
                         :prompt (.get prompts name "")))

      ;; client specifies nothing, so just list them
      :else
      (await (client-rpc sid "prompts"
                         :result (sorted
                                   (lfor [k v] (.items prompts)
                                     {"prompt" k "prompt text" v})
                                   :key :prompt))))))

(defn :async [rpc] providers [* sid #** kwargs]
  "List the providers available to clients."
  (await (client-rpc sid "providers"
                     :result (sorted (list (.keys (:providers cfg)))))))

(defn :async [rpc] commands [* sid #** kwargs]
  "List the commands advertised to clients."
  (await (client-rpc sid
                     "commands"
                     :result (lfor [k v] (.items rpcs)
                               :if v.__doc__
                               (let [sig (->> (signature v)
                                              (str)
                                              (re.sub r"sid, " "")
                                              (re.sub r", \*\*kwargs" "")
                                              (re.sub r"\(\*" "")
                                              (re.sub r"\)" "")
                                              (re.sub r", " " :")
                                              (re.sub r" :profile" "")
                                              (re.sub r" :provider" "")
                                              (re.sub r" :chat" "")
                                              (re.sub r"=['\w]+" ""))]
                                 {"command" k
                                  "kwargs" sig
                                  "docstring" v.__doc__})))))

(defn :async [rpc] vdbinfo [* sid profile #** kwargs]
  "Give info on the state of the vdb."
  (let [d-info (await (vdb-info :profile profile))]
    (await (echo :sid sid
                 :result (+ f"vdb for {profile}\n\n"
                            (tabulate (.items d-info)))))))


;; * chat management
;; TODO slight inconsistency between ws and chat management
;; -----------------------------------------------------------------------------

(defn :async [rpc] chats [* sid profile #** kwargs]
  "List the user's saved chats."
  (await (client-rpc sid "chats" :result (list-chats profile))))

(defn :async [rpc] destroy [* sid profile chat #** kwargs]
  "Destroy a chat (by default, the current chat)."
  (delete-chat profile chat)
  (await (messages :sid sid :profile profile :chat chat))
  (await (client-rpc sid "info" :result "Chat destroyed.")))

(defn :async [rpc] rename [* sid profile chat to #** kwargs]
  "Rename the user's chat."
  (rename-chat profile chat to)
  (await (chats :sid sid :profile profile)))

(defn :async [rpc] fork [* sid profile chat to #** kwargs]
  "Make a copy of the user's chat."
  (copy-chat profile chat to)
  (await (chats :sid sid :profile profile)))


;; * workspace management
;; -----------------------------------------------------------------------------

(defn :async [rpc] ws
  [*
   sid
   profile
   [drop False]
   [fname False]
   [text ""]
   [arxiv False]
   [news False]
   [url False]
   [wikipedia False]
   [youtube False]
   #** kwargs]
  "With kwargs `:drop fname`, completely remove file `drop` from the profile's workspace.
  With kwarg `:fname fname`, store `:text \"text\"` into a file in the profile's current workspace.
  With `:youtube id`, put the transcript of a youtube video in the workspace.
  With `:url \"url\"`, put a the contents of a url the workspace.
  With `:arxiv \"search topic\"`, put a the results of an arXiv search (abstracts) in the workspace.
  With `:wikipedia \"topic\"`, put a wikipedia article in the workspace.
  Otherwise List files available in a profile's workspace."
  (cond
    youtube
    (let [text (retrieve.youtube youtube :punctuate (:punctuate cfg False))
          fname f"youtube-{youtube}"]
      (write-ws profile fname text)
      (await (client-rpc sid "info" :result f"Loaded transcript for YouTube video {id} into context workspace.")))

    url
    (let [text (retrieve.url url)
          fname (retrieve.filename-from-url)]
      (write-ws profile fname text)
      (await (client-rpc sid "info" :result f"Loaded {url} into context workspace, saved as '{fname}'.")))

    arxiv
    (let [text (retrieve.arxiv arxiv)
          fname (short-id arxiv)]
      (write-ws profile fname text)
      (await (client-rpc sid "info" :result f"Loaded {url} into context workspace, saved as '{fname}'.")))

    news
    (let [text (retrieve.ddg-news news)
          fname (short-id news)]
      (write-ws profile fname text)
      (await (client-rpc sid "info" :result f"Loaded news query into context workspace, saved as '{fname}'.")))

    wikipedia
    (let [text (retrieve.wikipedia wikipedia)
          fname (short-id wikipedia)]
      (write-ws profile fname text)
      (await (client-rpc sid "info" :result f"Loaded wikipedia query into context workspace, saved as '{fname}'.")))

    (and fname text)
    (do
      (write-ws profile fname text)
      (await (client-rpc sid "info" :result f"Loaded file '{fname}' into context workspace.")))

    fname
    (await (client-rpc sid "info" :result (.join "\n\n" [f"Contents of workspace file {fname}:"
                                                         (get-ws profile fname)])))

    drop
    (do
      (drop-ws profile drop)
      (await (client-rpc sid "info" :result f"Dropped '{drop}' from context workspace.")))

    :else (await (client-rpc sid "workspace" :result (lfor fname (list-ws profile)
                                                           {"name" fname
                                                            "length" (token-count (get-ws profile fname))})))))


;; * management of messages
;; -----------------------------------------------------------------------------

(defn :async [rpc] messages [* sid profile chat #** kwargs]
  ;; no docstring so it doesn't advertise to clients
  ;;Send all the user's messages.
  (await (client-rpc sid
                     "messages"
                     :chat (get-chat profile chat)
                     :workspace (workspace-messages profile))))

(defn :async [rpc] undo [* sid profile chat #** kwargs]
  "Destroy the last message pair (default current chat)."
  (let [messages (cut (get-chat profile chat) -2)]
    (set-chat messages profile chat))
  (await (messages :sid sid :profile profile :chat chat)))

(defn :async [rpc] chat [* sid profile chat prompt-name line provider #** kwargs]
  ;; no docstring so it doesn't advertise to clients
  (await (client-rpc sid "echo" :result {"role" "user" "content" line}))
  (let [reply ""
        chunk ""
        system-prompt (get-prompt profile prompt-name)
        system-msg {"role" "system" "content" system-prompt}
        usr-msg {"role" "user" "content" line "timestamp" (time)}
        ws-msgs (workspace-messages profile)
        saved-messages (get-chat profile chat)
        [messages dropped] (truncate saved-messages
                                     :space (+ (:max-tokens cfg 600)
                                               (token-count system-prompt)
                                               (token-count ws-msgs)
                                               (token-count line))
                                     :provider provider)
        sent-messages [system-msg #* ws-msgs #* messages usr-msg]]
    (for [:async chunk (stream-completion provider sent-messages #** kwargs)]
      (+= reply chunk)
      (await (client-rpc sid "status" :result "streaming ✅"))
      (await (client-rpc sid "chunk" :result chunk :chat chat)))
    (await (client-rpc sid "chunk" :result "\n\n" :chat chat))
    (.append saved-messages usr-msg)
    (.append saved-messages {"role" "assistant" "content" (.strip reply) "timestamp" (time)})
    (set-chat saved-messages profile chat))
  (await (client-rpc sid "status" :result "ready ✅")))

(defn :async [rpc] vdb [* sid profile chat prompt-name query provider #** kwargs]
  "Do RAG using the vdb alongside the chat context to respond to the query.
  `prompt_name` optionally specifies use of a particular prompt (by name).
  `query` specifies the text of the query."
  ;; TODO consolidate with `chat` rpc.
  ;; FIXME  guard against final user message being too long;
  ;;        recursion depth in `truncate`?
  (await (client-rpc sid "status" :result "querying ⏳"))
  (await (client-rpc sid "echo" :result {"role" "user" "content" query}))
  (let [context-length (:context-length (get cfg "providers" provider) (:context-length cfg 30000))
        rag-line (await (vdb-extracts query :profile profile :max-length (/ context-length 2)))
        reply ""
        chunk ""
        system-prompt (get-prompt profile prompt-name)
        system-msg {"role" "system" "content" system-prompt}
        rag-usr-msg {"role" "user" "content" rag-line}
        saved-usr-msg {"role" "user" "content" query "timestamp" (time) "tool" "vdb"}
        ws-msgs (workspace-messages profile)
        saved-messages (get-chat profile chat)
        [messages dropped] (truncate saved-messages
                                     :space (+ (:max-tokens cfg 600)
                                               (token-count system-prompt)
                                               (token-count ws-msgs)
                                               (token-count rag-line))
                                     :provider provider)
        sent-messages [system-msg #* ws-msgs #* messages rag-usr-msg]]
    (for [:async chunk (stream-completion provider sent-messages #** kwargs)]
      (+= reply chunk)
      (await (client-rpc sid "status" :result "streaming ✅"))
      (await (client-rpc sid "chunk" :result chunk :chat chat)))
    (await (client-rpc sid "chunk" :result "\n\n" :chat chat))
    (.append saved-messages saved-usr-msg)
    (.append saved-messages {"role" "assistant" "content" (extract-output reply) "timestamp" (time)})
    (set-chat saved-messages profile chat))
  (await (client-rpc sid "status" :result "ready ✅")))

