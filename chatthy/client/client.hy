"
Implements client side of async ROUTER-DEALER pattern.
"

(require hyrule [-> ->>])

(import asyncio)

(import zmq)
(import zmq.asyncio)

(import hyjinx.wire [wrap unwrap keys handoff]) 

(import chatthy.client [state])


; socket receive timeout of 6s!
(setv TIMEOUT 5)

(setv context (zmq.asyncio.Context))
(setv _keys (keys state.config-file))

(defn start-socket []
  (setv socket (.socket context zmq.DEALER))
  (.setsockopt socket zmq.RCVTIMEO (* TIMEOUT 1000))
  (.connect socket (:server state.cfg))
  socket)

(setv socket (start-socket))


(defn :async send [data]
  "Send a message to the server."
  (try
    (await (.send socket (wrap data #** _keys)))
    (except [zmq.error.Again]
      {"method" "error" "result" "Send timeout"})))

(defn :async recv []
  "Receive a message."
  (try
    (let [msg (unwrap (await (.recv socket)))
          t (:sender-time msg 0)
          payload (:payload msg {"method" "error"
                                 "result" "Received message with no payload"})]
      {#** payload "server_time" t})
    ;; a timeout just means no msg received
    (except [zmq.error.Again])))

(defn :async server-rpc [method #** kwargs]
  "Send a message payload with method and profile."
  (await (send {"method" method
                "profile" state.profile
                #** kwargs})))
  
