"
Manages global -- (mostly) mutable -- server state, and its persistence.

Chats and account details are stored as simple json files.
"

(require hyrule.argmove [-> ->>])

(require hyjinx [defmethod])
(import hyjinx [config mkdir
                jload jsave jappend
                filenames])

(import functools [cache])
(import json)
(import os [unlink])
(import pathlib [Path])
(import platformdirs [user-config-dir])
(import shutil [rmtree])
(import time [time])

;; use config dir
;; (file-exists (Path (user-config-dir "chatthy") fname))

;; Identify and create the storage directory
;; -----------------------------------------------------------------------------

(setv cfg (config "server.toml"))
(setv storage-dir (:storage cfg "state"))

(mkdir storage_dir)
(mkdir f"{storage_dir}/accounts")

;; chat persistence
;; key is username, chat-id
;; -----------------------------------------------------------------------------

(defmethod get-chat [#^ str username #^ str chat-id]
  "Retrieve the chat."
  (or (jload f"state/chats/{username}/{chat_id}.json") []))

(defmethod set-chat [#^ list messages #^ str username #^ str chat-id]
  "Store the chat."
  (mkdir f"state/chats/{username}")
  (jsave messages f"state/chats/{username}/{chat_id}.json")
  messages)

(defmethod delete-chat [#^ str username #^ str chat-id]
  "Completely remove a chat."
  (try
    (unlink f"state/chats/{username}/{chat_id}.json")
    (except [FileNotFoundError])))
  
(defmethod list-chats [#^ str username]
  "List chats available to a user."
  (lfor f (filenames f"state/chats/{username}")
    (. (Path f) stem)))

;; accounts and identity
;; key is username
;; -----------------------------------------------------------------------------

(defmethod get-account [#^ str username]
  (when username
    (or (jload f"state/accounts/{username}.json") {})))

(defmethod set-account [#^ dict account #^ str username]
  (when username
    (jsave account f"state/accounts/{username}.json")
    account))

(defmethod update-account [#^ str username #** kwargs]
  "Update a player's details. You cannot change the name."
  (let [account (get-account username)]
    (set-account (| account kwargs) username)))

(defmethod delete-account [#^ str username]
  "Completely remove an account."
  (try
    (unlink f"state/accounts/{username}.json")
    (rmtree f"state/chats")
    (except [FileNotFoundError])))

(defn [cache] get-pubkey [#^ str username #^ str pub-key]
  "Store the public key if it's not already known.
  Return the stored public key. First-come first-served."
  (let [account (get-account username)]
    (if (and account (:public-key account None)) ; if there is an account and it has a stored key
        (:public-key account) ; then use that key, otherwise,
        (:public-key (update-account username
                           :last-accessed (time)
                           :public-key pub-key))))) ; store the provided key for next time

