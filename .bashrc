# ~/.bashrc: executed by bash(1) for non-login shells.
# see /usr/share/doc/bash/examples/startup-files (in the package bash-doc)
# for examples

# If not running interactively, don't do anything
case $- in
    *i*) ;;
      *) return;;
esac

# don't put duplicate lines or lines starting with space in the history.
# See bash(1) for more options
HISTCONTROL=ignoreboth

# append to the history file, don't overwrite it
shopt -s histappend

# for setting history length see HISTSIZE and HISTFILESIZE in bash(1)
HISTSIZE=10000
HISTFILESIZE=20000

# check the window size after each command and, if necessary,
# update the values of LINES and COLUMNS.
shopt -s checkwinsize

# If set, the pattern "**" used in a pathname expansion context will
# match all files and zero or more directories and subdirectories.
shopt -s globstar

# make less more friendly for non-text input files, see lesspipe(1)
[ -x /usr/bin/lesspipe ] && eval "$(SHELL=/bin/sh lesspipe)"

# set variable identifying the chroot you work in (used in the prompt below)
if [ -z "${debian_chroot:-}" ] && [ -r /etc/debian_chroot ]; then
    debian_chroot=$(cat /etc/debian_chroot)
fi

# set a fancy prompt (non-color, unless we know we "want" color)
case "$TERM" in
    xterm-color|*-256color) color_prompt=yes;;
esac

# uncomment for a colored prompt, if the terminal has the capability; turned
# off by default to not distract the user: the focus in a terminal window
# should be on the output of commands, not on the prompt
force_color_prompt=yes

if [ -n "$force_color_prompt" ]; then
    if [ -x /usr/bin/tput ] && tput setaf 1 >&/dev/null; then
        # We have color support; assume it's compliant with Ecma-48
        # (ISO/IEC-6429). (Lack of such support is extremely rare, and such
        # a case would tend to support setf rather than setaf.)
        color_prompt=yes
    else
        color_prompt=
    fi
fi

if [ "$color_prompt" = yes ]; then
    PS1='${debian_chroot:+($debian_chroot)}\[\033[01;32m\]\u@\h\[\033[00m\]:\[\033[01;34m\]\w\[\033[00m\]\$ '
else
    PS1='${debian_chroot:+($debian_chroot)}\u@\h:\w\$ '
fi
unset color_prompt force_color_prompt

# If this is an xterm set the title to user@host:dir
case "$TERM" in
xterm*|rxvt*)
    PS1="\[\e]0;${debian_chroot:+($debian_chroot)}\u@\h: \w\a\]$PS1"
    ;;
*)
    ;;
esac

# enable color support of ls and also add handy aliases
if [ -x /usr/bin/dircolors ]; then
    test -r ~/.dircolors && eval "$(dircolors -b ~/.dircolors)" || eval "$(dircolors -b)"
    alias ls='ls --color=auto'
    alias dir='dir --color=auto'
    alias vdir='vdir --color=auto'

    alias grep='grep --color=auto'
    alias fgrep='fgrep --color=auto'
    alias egrep='egrep --color=auto'
fi

# colored GCC warnings and errors
#export GCC_COLORS='error=01;31:warning=01;35:note=01;36:caret=01:locus=01:quote=01'

# ==========================================
# ALIASES
# ==========================================

# System aliases
alias update='sudo apt update && sudo apt upgrade -y'
alias clean='sudo apt autoremove --purge -y'
alias restart-net='sudo systemctl restart NetworkManager'
alias install='sudo apt install'
alias r='reboot'
alias q='exit'
alias c='clear'


# Navigation and file aliases
alias ll='ls -la --color=auto'
alias la='ls -A --color=auto'
alias l='ls -la --color=auto'
alias ..='cd ..'
alias ...='cd ../..'
alias mkdir='mkdir -p'

# Tool aliases
alias ff='fastfetch'
alias y='yazi'
alias hist='hstr'
alias tm='tmux'
alias tma='tmux attach -t'
alias tml='tmux list-sessions'
alias fetch='fastfetch'

# Git aliases
alias gs='git status'
alias ga='git add .'
alias gc='git commit -m'
alias gp='git push'
alias gpl='git pull'
alias gd='git diff'
alias gb='git branch'
alias gsw='git swtich'
alias gl='git log --graph'
# ==========================================
# KEYBOARD SHORTCUTS
# ==========================================

# Make Tab cycle through completion options
bind 'TAB: menu-complete'
bind 'set show-all-if-ambiguous on'
bind 'set menu-complete-display-prefix on'

# ==========================================
# AUTOCOMPLETE
# ==========================================

# Starship autocomplete
source <(starship completions bash)

# GitHub CLI autocomplete
source <(gh completion -s bash)

# HSTR autocomplete
source <(hstr --show-bash-configuration)

# ==========================================
# STARSHIP PROMPT
# ==========================================

eval "$(starship init bash)"

# ==========================================
# ENVIRONMENT
# ==========================================

# Terminal por defecto del workflow
export TERMINAL="kitty"

export PATH="$HOME/.npm-global/bin:$PATH"
export PATH="$HOME/.local/bin:$PATH"

# ==========================================
# FASTFETCH RANDOMIZER (kitty > chafa > ascii)
# ==========================================
# Toma pngs/gifs/ascii/videos de utils/ y los muestra con fastfetch:
# kitty con gráficos -> protocolo kitty; terminal normal + chafa -> color;
# sin gráficos -> ASCII. Se activa con cada `fastfetch`.

export FF_UTILS_DIR="$HOME/shell-workflow/utils"
export FF_RANDOMIZER="$HOME/shell-workflow/randomizer.sh"

# Fallback si el repo está en otra ruta (ej. checkout distinto)
if [ ! -x "$FF_RANDOMIZER" ]; then
    if [ -x "$(dirname "${BASH_SOURCE[0]:-$HOME/.bashrc}")/randomizer.sh" ]; then
        export FF_RANDOMIZER="$(dirname "${BASH_SOURCE[0]:-$HOME/.bashrc}")/randomizer.sh"
    fi
    _REPO_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$HOME/.bashrc}")" 2>/dev/null && pwd)"
    if [ -x "$_REPO_DIR/randomizer.sh" ]; then
        export FF_RANDOMIZER="$_REPO_DIR/randomizer.sh"
    fi
    unset _REPO_DIR
    # utils junto al randomizer tiene prioridad si existe
    _FF_DIR="$(dirname "$FF_RANDOMIZER" 2>/dev/null)"
    if [ -d "$_FF_DIR/utils" ]; then
        export FF_UTILS_DIR="$_FF_DIR/utils"
    fi
    unset _FF_DIR
fi

# Wrapper: cada `fastfetch`, `ff` o `fetch` pasa por el randomizer.
# Dentro de randomizer.sh se usa `command fastfetch` para no recursar.
if [ -x "$FF_RANDOMIZER" ]; then
    fastfetch() { bash "$FF_RANDOMIZER" "$@"; }
    ff() { bash "$FF_RANDOMIZER" "$@"; }
    fetch() { bash "$FF_RANDOMIZER" "$@"; }
fi
