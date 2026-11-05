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
# Over SSH the palette belongs to the terminal you're sitting at, so a riced
# remote shell must not repaint it with ITS accent — its prompt then shows in
# the local accent (it draws with the same slots). The exception is a VS Code
# Remote-SSH terminal: there is no local shell in it to send the slots, so it
# was left on the stock purples. The client's set-accent.sh pushes its palette
# lines to ~/.cache/client-accent here (on connect and on every accent change,
# see push_remote), and this sends those instead of our own.
_accent_src=
if [[ -t 1 && -z $GHOSTTY_RESOURCES_DIR ]]; then
  if [[ -z $SSH_CONNECTION ]]; then
    [[ -r ~/.config/ghostty/config ]] && _accent_src=~/.config/ghostty/config
  elif [[ $TERM_PROGRAM == vscode ]]; then
    _accent_src=~/.cache/client-accent     # may not exist yet: read once it does
  fi
fi
if [[ -n $_accent_src ]]; then
  zmodload -F zsh/stat b:zstat
  autoload -Uz add-zsh-hook
  _accent_osc() {
    local -a m; local slot
    zstat -A m +mtime $_accent_src 2>/dev/null || return 0
    if [[ $m[1] != $_accent_mtime ]]; then
      _accent_mtime=$m[1] _accent_seq=
      for slot in ${(f)"$(grep -o '^palette = 5[3-7]=#[0-9a-fA-F]\{6\}' $_accent_src)"}; do
        slot=${slot#palette = }                     # 53=#rrggbb
        _accent_seq+=$'\e]4;'"${slot%%=*};${slot#*=}"$'\e\\'
      done
    fi
    print -rn -- $_accent_seq
  }
  _accent_osc
  add-zsh-hook precmd _accent_osc
  # (not a remote one: this machine's set-accent.sh would retint it with ours)
  _accent_ttys=${XDG_RUNTIME_DIR:-/tmp}/accent-ttys
  if [[ -z $SSH_CONNECTION ]] && mkdir -p $_accent_ttys 2>/dev/null && print -r -- $TTY > $_accent_ttys/$$; then
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
  export FZF_ALT_C_OPTS="--preview 'eza --tree --color=always --icons {} | head -200'"
fi

# ─── Ctrl+T: yazi, for picking files or for moving around ──────────────────
# yazi opens full-screen at $PWD with all of its keys (→ into a folder, ← back
# out, Shift+←/→ and Shift+wheel to scroll the preview sideways, Space to
# select several, `z` for a recursive fuzzy find …). On the way out:
#
#   Enter   picks the hovered file or folder (or the selection): its path is
#           pasted at the cursor — relative when under $PWD, else ~/… or
#           absolute. Picking only PDFs with nothing typed yet opens them in
#           zathura instead, like yazi's own Enter.
#   q       quits; with nothing typed yet, the shell cd's to the folder you
#           were in (this replaced the old `y` function). With a half-typed
#           command on the line it stays put, so the command's relative paths
#           keep meaning what they did.
#   Q       quits and stays put, always.
_yazi_pick() {
  local pick cwdf f cwd
  pick="$(mktemp -t yazi-pick.XXXXXX)" || return 1
  cwdf="$(mktemp -t yazi-cwd.XXXXXX)" || { rm -f -- "$pick"; return 1; }
  zle -I
  # through yazi-live.sh: reopens in place on an accent change, and gets the
  # Shift+wheel translation
  ~/.config/yazi/yazi-live.sh --chooser-file="$pick" --cwd-file="$cwdf" </dev/tty >/dev/tty
  local -a picked=("${(@f)$(<$pick)}") words
  cwd="$(<$cwdf)"
  rm -f -- "$pick" "$cwdf"
  picked=(${picked:#})                       # drop empty lines
  if (( ${#picked} )); then
    local all_pdf=1
    for f in $picked; do [[ ${f:l} == *.pdf ]] || all_pdf=0; done
    if [[ -z $BUFFER ]] && (( all_pdf )); then
      for f in $picked; do setsid -f zathura -- "$f" >/dev/null 2>&1; done
    else
      for f in $picked; do
        if [[ $f == $PWD/* ]]; then words+=("${(q)${f#$PWD/}}")
        elif [[ $f == $HOME/* ]]; then words+=("~/${(q)${f#$HOME/}}")
        else words+=("${(q)f}"); fi
      done
      LBUFFER+="${(j: :)words} "
    fi
  elif [[ -z $BUFFER && -n $cwd && -d $cwd && $cwd != $PWD ]]; then
    builtin cd -- "$cwd"
    # the prompt is built in precmd, which a widget doesn't re-run
    (( $+functions[prompt_starship_precmd] )) && prompt_starship_precmd
  fi
  zle reset-prompt
}
zle -N _yazi_pick
bindkey -M emacs '^T' _yazi_pick

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
alias ff='fortunefetch'
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
# fastfetch with `fortune | cowsay` (accent, colour 1) under a logo: both go
# in as one logo, so the cow sits in the logo column. The logo, the cow and
# fastfetch's details are picked in Settings › Terminal, which writes
# ~/.config/fastfetch/greeting.env (FF_LOGO = a data logo file with $1/$2 =
# fastfetch logo colours, "" = none; FF_LOGO_SMALL = its small version; FF_COW
# = cow / random / "" = no fortune; FF_ARGS / FF_ARGS_SMALL = extra fastfetch
# args) — greeting.py there; without it, the small rice logo + the default
# cow. `$` in the fortune is doubled so fastfetch doesn't read it as a colour
# code. The animal is nudged up to 4 columns left (greeting.py's preview does
# the same) so with the default cow the logo column stays 27 wide and the info
# (63 wide, the cpu line) still fits a half-screen ghostty (91 cols).
#
# FF_COMPACT=1 (greeting.env or here) turns on the compact layout: when the
# full greeting is taller than the window (a top/bottom split, ~24 rows) the
# small logo, a short fortune (the cow only if it fits) and
# config-compact.jsonc (fewer details, ~19 rows) are drawn instead. Off: tiled
# terminals show the same greeting as big ones.

# $1 = cow, stdin = the fortune → REPLY = the cow as data-logo lines
function _ff_cowsay() {
  local -i i bub=0 shift=4
  local -a lines
  lines=("${(@f)$(/usr/games/cowsay -f "$1" -W 20 | expand)}")
  # the animal (below the bubble's last " ----" line) moves up to 4 columns left
  for i in {1..$#lines}; do [[ $lines[i] =~ '^ -+$' ]] && bub=$i; done
  if (( bub && bub < $#lines )); then
    for i in {$((bub + 1))..$#lines}; do
      [[ -n ${lines[i]// } ]] && (( ${#${lines[i]%%[^ ]*}} < shift )) && shift=${#${lines[i]%%[^ ]*}}
    done
    for i in {$((bub + 1))..$#lines}; do lines[i]=${lines[i]:$shift}; done
  fi
  REPLY=${(F)lines}
  REPLY=${REPLY//\$/\$\$}
  REPLY="${(F)${(@)${(f)REPLY}/#/\$1}}"
}
function fortunefetch() {
  local FF_LOGO=~/.config/fastfetch/ubuntu-small.txt FF_COW=default
  local FF_LOGO_SMALL=~/.config/fastfetch/ubuntu-small.txt FF_COMPACT=${FF_COMPACT:-0}
  local -a FF_ARGS FF_ARGS_SMALL cows
  [[ -r ~/.config/fastfetch/greeting.env ]] && source ~/.config/fastfetch/greeting.env
  _ff_args=("${FF_ARGS[@]}") _ff_args_small=("${FF_ARGS_SMALL[@]}") _ff_compact_on=$FF_COMPACT
  _ff_art= _ff_art_small= _ff_cow= _ff_cow_small= _ff_size= _ff_shown= _ff_compact=
  [[ -n $FF_LOGO && -r $FF_LOGO ]] && _ff_art="$(<$FF_LOGO)"
  [[ -n $FF_LOGO_SMALL && -r $FF_LOGO_SMALL ]] && _ff_art_small="$(<$FF_LOGO_SMALL)"
  _ff_cowname=
  if [[ -n $FF_COW && -x /usr/games/fortune && -x /usr/games/cowsay ]]; then
    if [[ $FF_COW == random ]]; then
      cows=(/usr/share/cowsay/cows/*.cow(N:t:r))
      FF_COW=${cows[RANDOM % $#cows + 1]:-default}
    fi
    _ff_cowname=$FF_COW
    _ff_cowsay $FF_COW < <(/usr/games/fortune -s)
    _ff_cow=$REPLY
  fi
  _ff_render && _ff_show $1
}

# $1 = logo art, $2 = cow → REPLY = both as one logo (blank line between)
function _ff_join() {
  if [[ -n $1 && -n $2 ]]; then REPLY="$1"$'\n\n'"$2"; else REPLY="$1$2"; fi
}
# $1 = full | compact → REPLY = fastfetch's output (trailing newlines kept)
function _ff_run() {
  local -a args
  if [[ $1 == compact ]]; then
    args=(-c ~/.config/fastfetch/config-compact.jsonc "${_ff_args_small[@]}")
    REPLY=$_ff_art_small
    if [[ -n $_ff_cowname ]]; then
      # a short fortune, made once per shell; the cow goes only if it fits
      [[ -z $_ff_cow_small ]] && { _ff_cowsay $_ff_cowname < <(/usr/games/fortune -s -n 60); _ff_cow_small=$REPLY; }
      (( ${#${(f)_ff_art_small}} + ${#${(f)_ff_cow_small}} + 1 <= LINES - 3 )) \
        && _ff_join "$_ff_art_small" "$_ff_cow_small"
    fi
  else
    args=("${_ff_args[@]}")
    _ff_join "$_ff_art" "$_ff_cow"
  fi
  if [[ -n $REPLY ]]; then args+=(--logo-type data --logo "$REPLY"); else args+=(-l none); fi
  REPLY="$(fastfetch --pipe false "${args[@]}"; print -n .)"
  REPLY=${REPLY%.}
}
# $1 = fastfetch output → REPLY = rows it takes (it draws the logo, then goes
# back up for the details)
function _ff_rows() {
  local s=$1
  local -i rows=${#${s//[^$'\n']/}}
  while [[ $s =~ $'\e\\[([0-9]+)A' ]]; do (( rows -= match[1] )); s=${s[MEND+1,-1]}; done
  REPLY=$rows
}
# REPLY = the greeting for this window size: full, or (FF_COMPACT=1) compact
# when the full one (+ the prompt) is taller than the window. Picked once per
# size.
function _ff_render() {
  command -v fastfetch >/dev/null || return 1
  if [[ $_ff_compact_on != 1 ]]; then
    _ff_compact=; _ff_run full
  elif [[ $COLUMNS:$LINES != $_ff_size ]]; then
    _ff_run full
    local out=$REPLY
    _ff_rows "$out"
    if (( REPLY + 3 > LINES )); then _ff_compact=1; _ff_run compact
    else _ff_compact=; REPLY=$out; fi
  else
    _ff_run ${${_ff_compact:+compact}:-full}
  fi
}
# print REPLY as one frame (synchronized output) and without line wrap, as
# fastfetch itself does. $1: top = from the top of a cleared screen, clear =
# also drop the scrollback
function _ff_show() {
  local cls
  case $1 in top) cls=$'\e[H\e[2J' ;; clear) cls=$'\e[H\e[2J\e[3J' ;; esac
  print -rn -- $'\e[?2026h'$cls$'\e[?7l'"$REPLY"$'\e[?7h\e[?2026l'
  _ff_shown=$REPLY _ff_size=$COLUMNS:$LINES
}

# Until the first command runs, the greeting stays live:
#  - a resize redraws it at the new size (a terminal that opens in a narrow
#    tile and is then widened would otherwise keep the squeezed layout, and a
#    top/bottom split gets the compact one);
#  - ~/.config/fastfetch/live.py watches what it shows (brightness, battery,
#    volume, network, the clock each minute) and pokes zsh through a pipe
#    (zle -F); fastfetch runs again and, if anything changed, the greeting
#    rows are rewritten in place — the cursor is saved and put back, so the
#    prompt (and whatever is typed) is never touched. Only if the greeting's
#    height changed is the screen cleared and the prompt redrawn under it.
# The greeting is drawn from the top of the screen so its rows are known.
# Running a command, an empty Enter (a second prompt) or Ctrl+L ends it;
# after that the greeting is plain scrollback.
if command -v fastfetch >/dev/null; then
  fortunefetch top
  if [[ -n $_ff_size ]]; then
    function _ff_redraw() {
      _ff_render || return
      [[ $REPLY == $_ff_shown && $COLUMNS:$LINES == $_ff_size ]] && return
      local new=$REPLY clr
      local -i old
      _ff_rows "$_ff_shown"; old=$REPLY
      _ff_rows "$new"
      if [[ $COLUMNS:$LINES == $_ff_size ]] && (( old + 3 > LINES )); then
        return                          # taller than the window: its top scrolled away
      elif [[ $COLUMNS:$LINES == $_ff_size ]] && (( REPLY == old )); then
        repeat $old clr+=$'\e[2K\e[B'
        print -rn -- $'\e7\e[?2026h\e[H'$clr$'\e[H\e[?7l'"$new"$'\e[?7h\e8\e[?2026l'
        _ff_shown=$new
      else
        REPLY=$new
        zle && zle -I                   # take the prompt down; zle redraws it after
        _ff_show clear
      fi
    }
    TRAPWINCH() { [[ $COLUMNS:$LINES == $_ff_size ]] || _ff_redraw }
    function _ff_live() {               # zle -F handler: live.py wrote a line
      local l fd=$1
      if ! read -r -u $fd l; then zle -F $fd; exec {fd}<&-; _ff_fd=; return; fi   # it quit
      while read -t 0 -r -u $fd l; do :; done
      _ff_redraw
    }
    function _ff_clear_screen() { _ff_greeting_done; zle .clear-screen }
    function _ff_prompts() {            # the 2nd prompt (an empty Enter) ends it
      (( ++_ff_nprompt > 1 )) && _ff_greeting_done
    }
    function _ff_greeting_done() {
      add-zsh-hook -d preexec _ff_greeting_done
      add-zsh-hook -d precmd _ff_prompts
      if [[ -n $_ff_fd ]]; then zle -F $_ff_fd 2>/dev/null; exec {_ff_fd}<&-; fi
      zle -A .clear-screen clear-screen
      unfunction TRAPWINCH _ff_greeting_done _ff_clear_screen _ff_live _ff_redraw _ff_prompts
      unset _ff_fd _ff_nprompt
    }
    if [[ -r ~/.config/fastfetch/live.py ]] && command -v python3 >/dev/null; then
      exec {_ff_fd}< <(exec python3 ~/.config/fastfetch/live.py </dev/null 2>/dev/null)
      zle -F $_ff_fd _ff_live
    fi
    zle -N clear-screen _ff_clear_screen
    autoload -Uz add-zsh-hook
    add-zsh-hook preexec _ff_greeting_done
    typeset -gi _ff_nprompt=0
    add-zsh-hook precmd _ff_prompts
  fi
fi

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
