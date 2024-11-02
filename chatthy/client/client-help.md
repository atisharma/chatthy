
  ┏┓┓     ┓
  ┃ ┣┓┏┓╋╋┣┓┓┏
  ┗┛┛┗┗┻┗┗┛┗┗┫
             ┛

# Client bindings

Most readline-compatible bindings are implemented.

## Input bindings

    F1                  show this help text
    Ctrl-q              quit
    Alt-m               toggle multiline input
    Shift-Tab           toggle focus between input and output
    Tab                 enter a command

## Output bindings

    Ctrl-b / PGUP       scroll output up one page
    Ctrl-f / PGDOWN     scroll output down one page
    Ctrl-l              refresh the output window
    Ctrl-c              cancel generation (not implemented)

# Commands (Shift-Tab)

## Client commands

    set :chat new-chat-name     switch to another chat
    set :prompt prompt-name     switch to saved system prompt

## Server commands (a selection)

    commands            list all advertised server commands
    chats               list existing chats
    destroy             destroy the current chat
    undo                destroy the last message pair in the chat

