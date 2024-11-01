
# Client input commands
    F1                show this help text
    Ctrl-l            toggle multiline input
    Ctrl-q            quit
    Shift-tab         send a server command

# Chat view and output
    Ctrl-b / PGUP     scroll output up one page
    Ctrl-f / PGDOWN   scroll output down one page
    Ctrl-r            refresh the output window
    Ctrl-c            cancel generation (not implemented)

# Commands (Shift-tab)
    chats             list existing chats
    commands          list advertised server commands
    destroy           destroy the current chat
    switch :chat-id new-chat-name
                      switch to another chat
    system :prompt \"A fancy new system prompt.\"
                      set the system prompt
    undo              destroy the last message pair in the chat

# Readline-compatible shortcuts (a selection)
    Ctrl-a            start of line
    Ctrl-e            end of line
    Ctrl-u            delete line
    Ctrl-u            delete back to start of line
    Ctrl-k            delete forward to end of line
    Ctrl-w            delete word behind cursor

