# Dotfiles directory
: "${DOTFILES_DIR:=$HOME/dotfiles}"

# Shell options
setopt AUTO_CD              # cd by typing directory name
setopt CORRECT              # suggest corrections for typos
typeset -U path             # deduplicate PATH entries

# Prompt: path, with hostname if SSH session
_is_ssh() {
    [[ -n "$SSH_CLIENT" || -n "$SSH_TTY" ]] && return 0
    # Check tmux's environment if we're in tmux
    if [[ -n "$TMUX" ]]; then
        tmux show-environment SSH_CLIENT 2>/dev/null | grep -q '^SSH_CLIENT=' && return 0
    fi
    return 1
}

if _is_ssh; then
    PROMPT='%F{146}%m %~%f '
else
    PROMPT='%F{146}%~%f '
fi
unset -f _is_ssh

# Completions
autoload -Uz compinit && compinit
autoload -Uz add-zsh-hook

# History
HISTFILE=~/.zsh_history
HISTSIZE=10000
SAVEHIST=10000
setopt EXTENDED_HISTORY
setopt HIST_IGNORE_DUPS
setopt HIST_IGNORE_SPACE
setopt HIST_REDUCE_BLANKS
setopt INC_APPEND_HISTORY

# History (zsh-histdb)
if [ -f ~/.zsh/plugins/zsh-histdb/sqlite-history.zsh ]; then
    source ~/.zsh/plugins/zsh-histdb/sqlite-history.zsh
    source ~/.zsh/plugins/zsh-histdb/histdb-interactive.zsh
    bindkey '^r' _histdb-isearch
fi

# Up/down search history by prefix
bindkey "^[[A" history-beginning-search-backward
bindkey "^[[B" history-beginning-search-forward

# Aliases
if [[ "$(uname)" == "Darwin" ]]; then
    alias ls="ls -G"
else
    alias ls="ls --color=auto"
fi
alias ll="ls -la"
alias la="ls -A"
alias ..="cd .."
alias ...="cd ../.."
alias md="mkdir -p"
alias http="python3 -m http.server"
alias hs="histdb"
alias g="git"
alias tma='tmux attach -d -t'
alias git-tmux='tmux new -s $(basename $(pwd))'

# Functions
make-proj() {
    if [ -z "$1" ]; then
        echo "Usage: make-proj <name>"
        return 1
    fi
    mkdir -p "$HOME/projects"
    local project_path="$HOME/projects/$(date +%Y_%m)_$1"
    mkdir -p "$project_path"
    cd "$project_path"
}

# jj workspace management
if [ -f ~/.zsh/jj-trees.zsh ]; then
    source ~/.zsh/jj-trees.zsh
fi

# Local overrides
if [ -f ~/.zshrc_local ]; then
    source ~/.zshrc_local
fi

# Add ~/bin to PATH if it exists
if [ -d ~/bin/ ]; then
    PATH="$HOME/bin/:$PATH"
fi

# Add ~/.tools to PATH
if [ -d ~/.tools ]; then
    PATH="$HOME/.tools:$PATH"
fi

# Dotfiles status notice on shell startup
if [ -f ~/.tools/dotfiles-status.zsh ]; then
    source ~/.tools/dotfiles-status.zsh
fi
