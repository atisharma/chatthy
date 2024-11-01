
# Client commands

    F1                show this help text
    Ctrl-q            quit
    Shift-tab         enter a command

# Client input bindings

    Alt-m             toggle multiline input

Most readline-compatible bindings are implemented.

# Client chat view and output

    Ctrl-b / PGUP     scroll output up one page
    Ctrl-f / PGDOWN   scroll output down one page
    Ctrl-r            refresh the output window
    Ctrl-c            cancel generation (not implemented)

    switch :chat-id new-chat-name
                      switch to another chat

# Server commands (Shift-tab)

    chats             list existing chats
    commands          list all advertised server commands
    destroy           destroy the current chat
    undo              destroy the last message pair in the chat
