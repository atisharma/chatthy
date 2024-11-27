"
Tools made available to the LLM.
"

(require hyrule [of])
(require hyjinx [defmethod])

(import inspect)

(import hyjinx [llm first last])

(import trag.retrieve [arxiv
                       calculator
                       ddg-answers
                       ddg-news
                       location
                       url
                       weather
                       youtube])


;; TODO how to get parameter descriptions?

;; list of exported tools (functions)
(setv tools [arxiv calculator ddg-answers ddg-news location url weather youtube])


(defmacro if-empty [x #* body]
  "If statement where x is tested for being `inspect._empty`."
  `(if (is ~x inspect._empty)
     ~@body))

(defmethod spec-anthropic [f]
  "Generate single Anthropic-compatible tool spec from a function based on its signature."
  (let [name f.__name__
        description f.__doc__
        sig (inspect.signature f)
        required (lfor [param-name param] (sig.parameters.items)
                   :if (is param.default inspect._empty)
                   param-name)
        properties (dfor [param-name param] (sig.parameters.items)
                     param-name {"type" (if-empty param.annotation
                                          "Any"
                                          (str param.annotation))
                                 "default" (if-empty param.default
                                             None
                                             param.default)})]
                                 ;"description" "parameter description"})]
    {"name" f.__name__
     "description" f.__doc__
     "input_schema" {"type" "object"
                     "properties" properties
                     "required" required}}))

(defmethod spec-openai [f]
  "Generate single OpenAI-compatible tool spec from a function based on its signature."
  (let [name f.__name__
        description f.__doc__
        sig (inspect.signature f)
        required (lfor [param-name param] (sig.parameters.items)
                   :if (is param.default inspect._empty)
                   param-name)
        properties (dfor [param-name param] (sig.parameters.items)
                     param-name {"type" (if-empty param.annotation
                                          "Any"
                                          (str param.annotation))
                                 "default" (if-empty param.default
                                             None
                                             param.default)})]
                                 ;"description" "parameter description"})]
    ["type" "function"
     "function" {"name" f.__name__
                 "description" f.__doc__
                 "parameters" {"type" "object"
                               "properties" properties
                               "required" required
                               "additionalProperties" False}}]))


(defmethod spec-openai [#^ list fs]
  "Generate list of OpenAI-compatible tool specs from list of functions."
  (lfor f fs
    (spec-openai f)))

(defmethod spec-anthropic [#^ list fs]
  "Generate list of OpenAI-compatible tool specs from list of functions."
  (lfor f fs
    (spec-anthropic f)))
