# From Ubuntu .bashrc:
# some more ls aliases
alias ll='ls -alF'
alias la='ls -A'
alias l='ls -CF'
alias ltr='ls -ltr'

# BoGo alias-es-es
alias xcsel='xclip -sel clip'
alias ag="ag $* --hidden"
alias gitus="git status"
#
#         VISUAL is typically configured in the main .bashrc, per machine
alias v='$VISUAL'

if [ -z "$VISUAL" ]; then export VISUAL=nvim; fi

export PATH="$PATH:$(dirname ${BASH_SOURCE[0]})"
