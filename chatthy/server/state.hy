"
Manages global mutable server state, and its persistence.

Chats and account details are stored as json files.
"

(require hyrule.argmove [-> ->>])

(require hyjinx [defmethod])
(import hyjinx [config mkdir
                jload jsave jappend
                filenames])

(import functools [cache])
(import json)
(import os [unlink rename])
(import pathlib [Path])
(import platformdirs [user-config-dir])
(import shutil [rmtree])
(import time [time])


;; TODO use config dir
;; (file-exists (Path (user-config-dir "chatthy") fname))

;; TODO proper Path objects so it works on non-unix

;; TODO rename chat


;; Identify and create the storage directory
;; -----------------------------------------------------------------------------

(setv cfg (config "server.toml"))
(setv storage-dir (:storage cfg "state"))
(setv accounts-dir f"{storage_dir}/accounts")
(setv chats-dir f"{storage_dir}/chats")

(mkdir storage-dir)
(mkdir accounts_dir)
(mkdir chats_dir)

;; chat persistence
;; key is username, chat
;; -----------------------------------------------------------------------------

(defmethod get-chat [#^ str username #^ str chat]
  "Retrieve the chat."
  (or (jload f"{chats_dir}/{username}/{chat}.json") []))

(defmethod set-chat [#^ list messages #^ str username #^ str chat]
  "Store the chat."
  (mkdir f"{chats_dir}/{username}")
  (jsave messages f"{chats_dir}/{username}/{chat}.json")
  messages)

(defmethod delete-chat [#^ str username #^ str chat]
  "Completely remove a chat."
  (try
    (unlink f"{chats_dir}/{username}/{chat}.json")
    (except [FileNotFoundError])))
  
(defmethod list-chats [#^ str username]
  "List chats available to a user."
  (lfor f (filenames f"{chats_dir}/{username}")
    (. (Path f) stem)))

(defmethod rename-chat [#^ str username #^ str chat #^ str to]
  "Move the file associated with `chat` to `to`."
  (rename
    f"{chats_dir}/{username}/{chat}.json"
    f"{chats_dir}/{username}/{to}.json"))

;; accounts and identity
;; key is username
;; -----------------------------------------------------------------------------

(defmethod get-account [#^ str username]
  (when username
    (or (jload f"{accounts_dir}/{username}.json") {})))

(defmethod set-account [#^ dict account #^ str username]
  (when username
    (jsave account f"{accounts_dir}/{username}.json")
    account))

(defmethod update-account [#^ str username #** kwargs]
  "Update a player's details. You cannot change the name."
  (let [account (get-account username)]
    (set-account (| account kwargs) username)))

(defmethod delete-account [#^ str username]
  "Completely remove an account."
  (try
    (unlink f"{accounts_dir}/{username}.json")
    (rmtree f"{chats_dir}/{username}")
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

