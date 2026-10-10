# ═══ zsh · Catppuccin Mocha rice ═══════════════════════════════════════════

export PATH="$HOME/.local/bin:$PATH"
export PATH="$PATH:$HOME/.spicetify"   # spicetify (Spotify theming)
export EDITOR="${EDITOR:-nano}"
export LANG=en_US.UTF-8

# ─── History ───────────────────────────────────────────────────────────────
HISTFILE=~/.zsh_history
HISTSIZE=100000
SAVEHIST=100000
setopt EXTENDED_HISTORY INC_APPEND_HISTORY SHARE_HISTORY
setopt HIST_IGNORE_DUPS HIST_IGNORE_ALL_DUPS HIST_IGNORE_SPACE
setopt HIST_FIND_NO_DUPS HIST_SAVE_NO_DUPS HIST_REDUCE_BLANKS
setopt AUTO_CD AUTO_PUSHD PUSHD_IGNORE_DUPS INTERACTIVE_COMMENTS
setopt GLOB_DOTS NO_BEEP

# ─── Completion ────────────────────────────────────────────────────────────
autoload -Uz compinit
# only rebuild the dump once a day -> faster startup
if [[ -n ~/.zcompdump(#qN.mh+24) ]]; then compinit; else compinit -C; fi

zstyle ':completion:*' menu select
zstyle ':completion:*' matcher-list 'm:{a-zA-Z}={A-Za-z}' 'r:|=*' 'l:|=* r:|=*'
zstyle ':completion:*' list-colors 'di=34:ln=36:so=35:pi=33:ex=32:bd=33:cd=33:su=31:sg=31:tw=34:ow=34'
zstyle ':completion:*:descriptions' format '%F{#cba6f7}─ %d ─%f'
zstyle ':completion:*:warnings'     format '%F{#f38ba8}no matches%f'
zstyle ':completion:*' group-name ''
zstyle ':completion:*' special-dirs true
zstyle ':completion:*' use-cache on
zstyle ':completion:*' cache-path ~/.cache/zsh/zcompcache

# ─── Keybinds ──────────────────────────────────────────────────────────────
bindkey -e
bindkey '^[[A' history-search-backward     # Up   = prefix search
bindkey '^[[B' history-search-forward      # Down = prefix search
bindkey '^[[1;5C' forward-word             # Ctrl+Right
bindkey '^[[1;5D' backward-word            # Ctrl+Left
bindkey '^[[3~' delete-char
bindkey '^[[H' beginning-of-line
bindkey '^[[F' end-of-line

# ─── Plugins (apt-installed) ───────────────────────────────────────────────
ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE='fg=#6c7086'
ZSH_AUTOSUGGEST_STRATEGY=(history completion)
[[ -f /usr/share/zsh-autosuggestions/zsh-autosuggestions.zsh ]] \
  && source /usr/share/zsh-autosuggestions/zsh-autosuggestions.zsh
bindkey '^ ' autosuggest-accept            # Ctrl+Space accepts the ghost text

# ─── Tool integrations ─────────────────────────────────────────────────────
command -v starship >/dev/null && eval "$(starship init zsh)"

if command -v fzf >/dev/null; then
  source <(fzf --zsh) 2>/dev/null
  export FZF_DEFAULT_OPTS="\
--height 55% --layout=reverse --border=rounded --info=inline-right --marker='▌' \
--color=bg+:#313244,bg:#1e1e2e,spinner:#f5e0dc,hl:#f38ba8 \
--color=fg:#cdd6f4,header:#f38ba8,info:#cba6f7,pointer:#f5e0dc \
--color=marker:#a6e3a1,fg+:#cdd6f4,prompt:#cba6f7,hl+:#f38ba8 \
--color=border:#585b70 --prompt='  ' --pointer='▶'"
  command -v fdfind >/dev/null && export FZF_DEFAULT_COMMAND='fdfind --hidden --strip-cwd-prefix --exclude .git'
  export FZF_CTRL_T_COMMAND="$FZF_DEFAULT_COMMAND"
  command -v batcat >/dev/null && export FZF_CTRL_T_OPTS="--preview 'batcat -n --color=always --line-range :300 {}'"
  export FZF_ALT_C_OPTS="--preview 'eza --tree --color=always --icons {} | head -200'"
fi

# ─── Aliases ───────────────────────────────────────────────────────────────
if command -v eza >/dev/null; then
  # Functions, not aliases: default to "." so eza doesn't read paths from a non-tty stdin
  unalias ls ll la lt ltt 2>/dev/null
  function ls  { eza --icons --group-directories-first "${@:-.}"; }
  function ll  { eza -lh --icons --group-directories-first --git "${@:-.}"; }
  function la  { eza -lah --icons --group-directories-first --git "${@:-.}"; }
  function lt  { eza --tree --level=2 --icons --group-directories-first "${@:-.}"; }
  function ltt { eza --tree --level=4 --icons --group-directories-first "${@:-.}"; }
else
  alias ll='ls -lh'; alias la='ls -lah'
fi

if command -v batcat >/dev/null; then
  alias cat='batcat --style=plain --paging=never'
  alias bat='batcat'
  export MANPAGER="sh -c 'col -bx | batcat -l man -p'"
  export MANROFFOPT='-c'
fi

command -v fdfind  >/dev/null && alias fd='fdfind'
command -v btop    >/dev/null && alias top='btop'
command -v zellij  >/dev/null && alias zj='zellij'

alias ..='cd ..'
alias ...='cd ../..'
alias ....='cd ../../..'
alias mkdir='mkdir -p'
alias df='df -h'
alias free='free -h'
alias ip='ip --color=auto'
alias grep='grep --color=auto'
alias please='sudo $(fc -ln -1)'
alias reload='exec zsh'
alias ff='fastfetch'
alias gs='git status -sb'
alias gl="git log --oneline --graph --decorate --all -20"
alias gd='git diff'
alias ga='git add'
alias gc='git commit'
alias gp='git push'

# ─── yazi: cd to the directory you quit in (press q) ───────────────────────
function y() {
  local tmp="$(mktemp -t yazi-cwd.XXXXXX)" cwd
  yazi "$@" --cwd-file="$tmp"
  if cwd="$(command cat -- "$tmp")" && [ -n "$cwd" ] && [ "$cwd" != "$PWD" ]; then
    builtin cd -- "$cwd"
  fi
  rm -f -- "$tmp"
}

# mkdir + cd in one go
function mkcd() { mkdir -p "$1" && cd "$1"; }

# extract anything
function extract() {
  case "$1" in
    *.tar.bz2) tar xjf "$1" ;;  *.tar.gz)  tar xzf "$1" ;;
    *.tar.xz)  tar xJf "$1" ;;  *.tar)     tar xf  "$1" ;;
    *.bz2)     bunzip2 "$1" ;;  *.gz)      gunzip  "$1" ;;
    *.zip)     unzip "$1"   ;;  *.7z)      7z x    "$1" ;;
    *.rar)     unrar x "$1" ;;  *.tbz2)    tar xjf "$1" ;;
    *.tgz)     tar xzf "$1" ;;  *.Z)       uncompress "$1" ;;
    *) echo "extract: don't know how to handle '$1'" ;;
  esac
}

# ─── Greeting ──────────────────────────────────────────────────────────────
command -v fastfetch >/dev/null && fastfetch

# ─── Syntax highlighting MUST be sourced last ──────────────────────────────
[[ -f /usr/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh ]] \
  && source /usr/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
typeset -gA ZSH_HIGHLIGHT_STYLES
ZSH_HIGHLIGHT_STYLES[command]='fg=#a6e3a1,bold'
ZSH_HIGHLIGHT_STYLES[builtin]='fg=#a6e3a1,bold'
ZSH_HIGHLIGHT_STYLES[function]='fg=#a6e3a1,bold'
ZSH_HIGHLIGHT_STYLES[alias]='fg=#a6e3a1,bold'
ZSH_HIGHLIGHT_STYLES[precommand]='fg=#a6e3a1,italic'
ZSH_HIGHLIGHT_STYLES[unknown-token]='fg=#f38ba8,bold'
ZSH_HIGHLIGHT_STYLES[path]='fg=#cdd6f4,underline'
ZSH_HIGHLIGHT_STYLES[single-quoted-argument]='fg=#f9e2af'
ZSH_HIGHLIGHT_STYLES[double-quoted-argument]='fg=#f9e2af'
ZSH_HIGHLIGHT_STYLES[comment]='fg=#6c7086,italic'
ZSH_HIGHLIGHT_STYLES[redirection]='fg=#f5c2e7'
ZSH_HIGHLIGHT_STYLES[commandseparator]='fg=#f5c2e7'


# >>> conda initialize >>>
# !! Contents within this block are managed by 'conda init' !!
__conda_setup="$("$HOME/miniconda3/bin/conda" 'shell.zsh' 'hook' 2> /dev/null)"
if [ $? -eq 0 ]; then
    eval "$__conda_setup"
else
    if [ -f "$HOME/miniconda3/etc/profile.d/conda.sh" ]; then
        . "$HOME/miniconda3/etc/profile.d/conda.sh"
    else
        export PATH="$HOME/miniconda3/bin:$PATH"
    fi
fi
unset __conda_setup
# <<< conda initialize <<<

# ─── curl/wget file downloads at the prompt go through JDownloader ─────────
[[ -r ~/.config/dl-popup/terminal.zsh ]] && source ~/.config/dl-popup/terminal.zsh

# ─── zoxide must init LAST (after syntax highlighting) ─────────────────────
# Claude Code's shell snapshot drops zoxide's chpwd hook, which trips zoxide's doctor
[[ -n $CLAUDECODE ]] && export _ZO_DOCTOR=0
command -v zoxide >/dev/null && eval "$(zoxide init zsh --cmd cd)"
