# chatthy

An asynchronous terminal server/multiple-client setup for conducting and managing chats with LLMs.

This is the successor project to [llama-farm](https://github.com/atisharma/llama_farm)

The RAG/agent functionality should be split out into an API layer.


### network architecture

- [x] client/server RPC-type architecture
- [x] message signing
- [ ] ensure chunk ordering


### chat management

- [x] basic chat persistence and management
- [x] set, switch to saved system prompts (personalities)
- [ ] manage prompts like chats (as files)
- [x] chat truncation to token length
- [x] rename chat
- [x] profiles (profile x personalities -> sets of chats)
- [ ] import/export chat to local file


### context workspace

- [x] context workspace (load/drop files)
- [x] client inject from file
- [x] client inject from other sources, e.g. youtube (trag)
- [x] templates for standard instruction requests (trag)
- [x] context workspace - bench/suspend files (hidden by filename)
- [ ] local files / folders in transient workspace
- [ ] checkboxes for delete / show / hide


### client interface

- [x] can switch between Anthropic, OpenAI, tabbyAPI providers and models
- [x] streaming
- [x] syntax highlighting
- [x] decent REPL
- [x] REPL command mode
- [x] cut/copy from output
- [x] client-side prompt editing
- [ ] vimish keys in output
- [ ] client-side chat/message editing (how? temporarily set the input field history? Fire up `$EDITOR` in client?)
        - edit via chat local import/export
- [ ] latex rendering (this is tricky in the context of prompt-toolkit, but see flatlatex).
- [ ] generation cancellation


### multimodal

- [ ] design with multimodal models in mind
- [ ] image sending and use
- [ ] image display


### miscellaneous / extensions

- [x] use proper config dir (group?)
- [ ] dump default conf if missing


### tool / agentic use

Use agents at the API level, which is to say, use an intelligent router.
This separates the chatthy system from the RAG/LLM logic.

- [ ] (auto) tools (evolve from llama-farm -> trag)
- [ ] user defined tool plugins
- [ ] server use vdb context at LLM will (tool)
- [ ] iterative workflows (refer to llama-farm)
- [ ] tool chains
- [ ] tool: workspace file write, delete
- [ ] tool: workspace file patch/diff
- [ ] tool: rag query tool
- [ ] MCP agents?
- [ ] smolagents / archgw?


### RAG

- [x] summaries and standard client instructions (trag)
- [x] server use vdb context on request
- [ ] consider best method of pdf conversion / ingestion, OOB
- [ ] full arxiv paper ingestion (fvdb) - consolidate into one latex file OOB
- [ ] vdb result reranking with context, and winnowing (agent?)
- [ ] vdb results -> workspace (agent?)


## unallocated / out of scope

audio streaming ? - see matatonic's servers
workflows (tree of instruction templates)
tasks

arXiv paper -> latex / md
pdf paper -> latex / md

