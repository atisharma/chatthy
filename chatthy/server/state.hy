"
Manages global mutable server state, and its persistence.

Chats and account details are stored as json files.
"

(require hyrule [-> ->> unless])

(import hyrule [assoc])

(require hyjinx [defmethod])
(import hyjinx [config mkdir
                spit slurp
                jload jsave jappend
                filenames])

(import asyncio)
(import functools [cache])
(import json)
(import os [unlink rename])
(import pathlib [Path])
(import platformdirs [user-config-dir])
(import re)
(import shutil [rmtree copyfile])
(import time [time])

(import zmq)
(import zmq.asyncio)

(import fvdb [faiss write])


;; TODO consistently use Path objects so it works on non-unix

  
;; * zmq server state
;; -----------------------------------------------------------------------------

(setv context (zmq.asyncio.Context))
(setv socket (.socket context zmq.ROUTER))


;; * Identify and access the storage directory
;; -----------------------------------------------------------------------------

;; look for ~/.config/chatthy/server.toml
;; or default to $pwd/server.toml
(let [p (Path (user-config-dir "chatthy") "server.toml")]
  (if (.exists p)
    (setv config-file p)
    (setv config-file "server.toml")))

(setv cfg (config config-file))
(setv storage-dir (:storage cfg "state"))

(defn sanitize [profile]
  "Lowercase profile name, no funny business."
  (->> profile
       (re.sub r"\W+" "")
       (.lower)))

(defn profile-dir [#^ str profile #* args]
  "Return the directory under which the profile's data is stored,
  or its subdirs (via `args`)."
  (let [pdir (Path storage-dir (sanitize profile) #* args)]
    (.mkdir pdir :parents True :exist-ok True)
    pdir))


;; * workspace (files stuffed into the context)
;; key is profile, filename
;; -----------------------------------------------------------------------------

(defmethod get-ws [#^ str profile #^ (| str Path) fname]
  "Return a file from the profile's workspace."
  (slurp (Path (profile-dir profile "workspace") fname)))

(defmethod write-ws
  [#^ str profile
   #^ (| str Path) fname
   #^ str text]
  "Return a file from the profile's workspace."
  (let [p (str (Path (profile-dir profile "workspace") fname))]
    (spit p text)))

(defmethod drop-ws [#^ str profile #^ (| str Path) fname]
  "Completely remove a file from the profile's workspace."
  (try
    (unlink (Path (profile-dir profile "workspace") fname))
    (except [FileNotFoundError])))
  
(defmethod rename-ws [#^ str profile #^ (| str Path) fname #^ str to]
  "Move the file associated with `fname` to `to`."
  (rename
    (Path (profile-dir profile "workspace") fname)
    (Path (profile-dir profile "workspace") to)))

(defmethod list-ws [#^ str profile * [include-ignored True]]
  "List files available in a profile's workspace.
  Files starting with \"__\" are ignored."
  (let [fnames (lfor f (filenames (profile-dir profile "workspace"))
                 (. (Path f) name))]
    (lfor fname fnames
      :if (or include-ignored (not (.startswith fname "__")))
      fname)))


;; * Vector DB
;; key is profile
;; -----------------------------------------------------------------------------

(setv vdbs {})

(defn :async get-vdb [#^ str profile * [reload False]]
  "Return the vdb for that profile.
  Create one if it doesn't exist."
  (let [p (sanitize profile)
        vdb (.get vdbs p None)]
    (if (and vdb (not reload))
      vdb ; use if it exists
      (do ; or create/load a new one
        (let [new-vdb (await (asyncio.to-thread faiss (profile-dir p "vdb")))]
          (assoc vdbs p new-vdb)
          (unless reload
            (write new-vdb))
          new-vdb)))))


;; * chat persistence
;; key is profile, chat
;; -----------------------------------------------------------------------------

(defmethod get-chat [#^ str profile #^ str chat]
  "Retrieve the chat."
  (or (jload (Path (profile-dir profile "chats") f"{chat}.json"))
      []))

(defmethod set-chat [#^ list messages #^ str profile #^ str chat]
  "Store the chat."
  (jsave messages (Path (profile-dir profile "chats") f"{chat}.json"))
  messages)

(defmethod delete-chat [#^ str profile #^ str chat]
  "Completely remove a chat."
  (try
    (unlink (Path (profile-dir profile "chats") f"{chat}.json"))
    (except [FileNotFoundError])))
  
(defmethod list-chats [#^ str profile]
  "List chats available to a profile."
  (lfor f (filenames (profile-dir profile "chats"))
    :if (= (. (Path f) suffix) ".json")
    (. (Path f) stem)))

(defmethod rename-chat [#^ str profile #^ str chat #^ str to]
  "Move the file associated with `chat` to `to`."
  (rename
    (Path (profile-dir profile "chats") f"{chat}.json")
    (Path (profile-dir profile "chats") f"{to}.json")))

(defmethod copy-chat [#^ str profile #^ str chat #^ str to]
  "Cupy the file associated with `chat` to `to`."
  (copyfile
    (Path (profile-dir profile "chats") f"{chat}.json")
    (Path (profile-dir profile "chats") f"{to}.json")))


;; * accounts and identity
;; key is profile
;; -----------------------------------------------------------------------------

(defmethod get-account [#^ str profile]
  (or (jload (Path (profile-dir profile) "account.json"))
      {}))

(defmethod set-account [#^ dict account #^ str profile]
  (when profile
    (jsave account (Path (profile-dir profile) "account.json"))
    account))

(defmethod update-account [#^ str profile #** kwargs]
  "Update a player's details. You cannot change the name."
  (let [account (get-account profile)]
    (set-account (| account kwargs) profile)))

(defmethod delete-account [#^ str profile]
  "Completely remove an account."
  (try
    (rmtree (profile-dir profile))
    (except [FileNotFoundError])))

(defn [cache] get-pubkey [#^ str profile #^ str pub-key]
  "Store the public key if it's not already known.
  Return the stored public key. First-come first-served."
  (let [account (get-account profile)]
    (if (and account (:public-key account None)) ; if there is an account and it has a stored key
        (:public-key account) ; then use that key, otherwise,
        (:public-key (update-account profile
                           :last-accessed (time)
                           :public-key pub-key))))) ; store the provided key for next time


;; * prompts
;; -----------------------------------------------------------------------------

(defmethod get-prompts [#^ str profile]
  "Get merged user-defined and server-defined prompts."
  (let [prompts (:prompts (get-account profile))]
    (| (:prompts cfg) prompts)))

(defmethod get-prompt [#^ str profile #^ str prompt-name]
  "Get a prompt by name."
  (let [prompts (get-prompts profile)]
    (.get prompts prompt-name (:default prompts))))

(defmethod update-prompt [#^ str profile #^ str prompt-name #^ str prompt]
  "Set/overwrite a prompt."
  (update-account profile :prompts (| prompts {name prompt})))
