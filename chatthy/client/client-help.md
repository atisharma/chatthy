
    ┏┓┓     ┓
    ┃ ┣┓┏┓╋╋┣┓┓┏
    ┗┛┛┗┗┻┗┗┛┗┗┫
              ┗┛

# Client bindings

Most readline-compatible bindings are implemented.

## Input bindings

    F1                          show this help text
    Ctrl-q                      quit
    Ctrl-l                      refresh message window
    Ctrl-v                      enable RAG using the vdb for this input
    Alt-m                       toggle multiline input
    Shift-Tab                   toggle focus between input and output
    Tab                         input a command
    Enter (Esc-Enter)           dispatch a command (multiline)

## Output bindings

    Ctrl-b / PGUP               scroll output up one page
    Ctrl-f / PGDOWN             scroll output down one page
    Ctrl-l                      refresh the output window
    Ctrl-c                      cancel generation (not implemented)

# Commands (Shift-Tab)

## Client commands

    load :chat new-chat-name    switch to another chat
    load :profile profile-name  switch to a different profile (same passphrase)
    load :prompt prompt-name    switch to saved system prompt
    load :provider prov-name    switch to a different provider (model)
    load :input filename        load a text file into the input field
    load :ws filename           load a text file into the model's context

## Server commands (use `commands` for full list)

    commands                    list all advertised server commands
    chats                       list existing chats
    destroy                     destroy the current chat
    undo                        destroy the last message pair in the chat
    ws :drop fname              drop `fname` from the workspace (context)
    ws :youtube Cv4-PdtPqJ8     add transcript into workspace

