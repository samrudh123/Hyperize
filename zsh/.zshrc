# ═══ zsh · Catppuccin Mocha rice ═══════════════════════════════════════════

export PATH="$HOME/.local/bin:$PATH"
export PATH="$PATH:$HOME/.spicetify"   # spicetify (Spotify theming)
export EDITOR="${EDITOR:-nvim}"
export VISUAL="$EDITOR"
export LANG=en_US.UTF-8

# ─── Accent ────────────────────────────────────────────────────────────────
# Everything accent-coloured in the shell (prompt, fastfetch, eza, completion,
# fzf) draws with 256-colour slots 53-57 instead of a hex: 53 accent, 54 its
# complement, 55/56 dark tints, 57 a third hue (fastfetch's hardware block). Ghostty's config maps those slots to the
# desktop accent (set-accent.sh renders it and reloads ghostty), and text keeps
# the slot, so an accent change recolours open terminals live — scrollback
# included. Other terminals (VS Code, GNOME Terminal, …) don't know the
# mapping: the shell teaches them with OSC 4, and registers its tty so
# set-accent.sh can re-send it live on every accent change.
#
# It also re-sends before every prompt, because VS Code forgets: any theme
# change — including the accent rewriting its settings.json — or a window
# reload resets the terminal to the stock xterm palette, where 53/54 are dark
# purples (VS Code's contrast boost then shows both as the same muted mauve).
# The config is only re-read when its mtime changes, so this costs one stat.
# Skipped over SSH: the palette belongs to the terminal you're sitting at, so
# a riced remote shell must not repaint it with ITS accent — its prompt then
# shows in the local accent (it draws with the same slots).
if [[ -z $SSH_CONNECTION && -z $GHOSTTY_RESOURCES_DIR && -t 1 && -r ~/.config/ghostty/config ]]; then
  zmodload -F zsh/stat b:zstat
  autoload -Uz add-zsh-hook
  _accent_osc() {
    local -a m; local slot
    zstat -A m +mtime ~/.config/ghostty/config 2>/dev/null || return 0
    if [[ $m[1] != $_accent_mtime ]]; then
      _accent_mtime=$m[1] _accent_seq=
      for slot in ${(f)"$(grep -o '^palette = 5[3-7]=#[0-9a-fA-F]\{6\}' ~/.config/ghostty/config)"}; do
        slot=${slot#palette = }                     # 53=#rrggbb
        _accent_seq+=$'\e]4;'"${slot%%=*};${slot#*=}"$'\e\\'
      done
    fi
    print -rn -- $_accent_seq
  }
  _accent_osc
  add-zsh-hook precmd _accent_osc
  _accent_ttys=${XDG_RUNTIME_DIR:-/tmp}/accent-ttys
  if mkdir -p $_accent_ttys 2>/dev/null && print -r -- $TTY > $_accent_ttys/$$; then
    _accent_tty_unregister() { rm -f $_accent_ttys/$$ }
    add-zsh-hook zshexit _accent_tty_unregister
  fi
  # VS Code only opens a terminal's xterm.js when its tab is first shown, and
  # until then silently drops OSC 4 — so a background terminal (e.g. restored
  # on startup) ate the startup send above and showed the stock palette until
  # its next prompt. Opening also resets the palette. Fix: while at a prompt,
  # ask for focus reports (DECSET 1004) and re-send on focus-in (ESC [ I),
  # which arrives right after the tab is shown — or when the window regains
  # focus after an accent change. Off while a command runs, so programs never
  # see the reports as input.
  if [[ $TERM_PROGRAM == vscode ]]; then
    _accent_focus_on()  { print -rn -- $'\e[?1004h' }
    _accent_focus_off() { print -rn -- $'\e[?1004l' }
    _accent_focus_in()  { _accent_osc }
    _accent_focus_out() { }
    zle -N _accent_focus_in
    zle -N _accent_focus_out
    for _km in emacs viins vicmd; do
      bindkey -M $_km '\e[I' _accent_focus_in '\e[O' _accent_focus_out
    done
    unset _km
    add-zsh-hook precmd _accent_focus_on
    add-zsh-hook preexec _accent_focus_off
  fi
fi

# ssh: a remote shell that does send OSC 4 (an older copy of this file,
# another rice) leaves its accent in this terminal after you disconnect.
# Elsewhere the next prompt's re-send repairs that, but Ghostty shells don't
# re-send, so reset slots 53-57 to the config palette (OSC 104 — tested: it
# restores Ghostty's configured value; leaves no override behind to fight
# later accent reloads).
if [[ -n $GHOSTTY_RESOURCES_DIR && -z $SSH_CONNECTION ]]; then
  ssh() {
    command ssh "$@"
    local rc=$?
    [[ -w $TTY ]] && print -rn -- $'\e]104;53;54;55;56;57\e\\' > $TTY
    return rc
  }
fi

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
zstyle ':completion:*' list-colors 'di=1;38;5;53:ln=36:so=35:pi=33:ex=32:bd=33:cd=33:su=31:sg=31:tw=38;5;53:ow=38;5;53'
zstyle ':completion:*:descriptions' format '%F{53}─ %d ─%f'
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
--color=fg:#cdd6f4,header:#f38ba8,info:53,pointer:53 \
--color=marker:#a6e3a1,fg+:#cdd6f4,prompt:53,hl+:#f38ba8 \
--color=border:#585b70 --prompt='  ' --pointer='▶'"
  command -v fdfind >/dev/null && export FZF_DEFAULT_COMMAND='fdfind --hidden --strip-cwd-prefix --exclude .git'
  export FZF_CTRL_T_COMMAND="$FZF_DEFAULT_COMMAND"
  command -v batcat >/dev/null && export FZF_CTRL_T_OPTS="--preview 'batcat -n --color=always --line-range :300 {}'"
  export FZF_ALT_C_OPTS="--preview 'eza --tree --color=always --icons {} | head -200'"
fi

# Claude Code in VS Code: the classic renderer ("tui": "default" in
# ~/.claude/settings.json) prints the transcript into the terminal's own
# scrollback at the width of the moment, so a session squeezed by tiling stays
# squeezed after the window widens again. The fullscreen renderer redraws the
# whole conversation on every resize (this env var overrides the setting).
[[ $TERM_PROGRAM == vscode ]] && export CLAUDE_CODE_NO_FLICKER=1

# ─── Aliases ───────────────────────────────────────────────────────────────
if command -v eza >/dev/null; then
  export EZA_COLORS='di=1;38;5;53'   # directories in the accent, like the prompt
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

# In the dotfiles repo, settle accent / theme picks before `git status`:
# set-accent.sh's git filter hides them, but git skips it for a file whose
# SIZE changed until --git-refresh has run, and a theme switch takes a few
# seconds to get there — so an instant `git status` listed them.
function git() {
  if [[ $1 == status && ${PWD:A}/ == $HOME/Hyperize/* && -x ~/.config/hypr/set-accent.sh ]]; then
    ~/.config/hypr/set-accent.sh --git-refresh 2>/dev/null
  fi
  command git "$@"
}

# ─── yazi: cd to the directory you quit in (press q) ───────────────────────
function y() {
  local tmp="$(mktemp -t yazi-cwd.XXXXXX)" cwd
  # through yazi-live.sh so it reopens in place on an accent / theme change
  ~/.config/yazi/yazi-live.sh "$@" --cwd-file="$tmp"
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


# venv's activate script would prefix "(name)" to the prompt, on a line of
# its own above starship's; starship shows the venv itself (custom.venv), as
# it does conda (changeps1: false in ~/.condarc).
export VIRTUAL_ENV_DISABLE_PROMPT=1

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
# Claude Code's shell snapshot drops zoxide's chpwd hook (tripping zoxide's doctor) and keeps
# functions but not env vars, so _ZO_DOCTOR=0 can't survive — skip zoxide there (builtin cd)
[[ -z $CLAUDECODE ]] && command -v zoxide >/dev/null && eval "$(zoxide init zsh --cmd cd)"
