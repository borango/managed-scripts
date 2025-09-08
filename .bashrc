# From Ubuntu .bashrc:
# some more ls aliases
alias ll='ls -alF'
alias la='ls -A'
alias l='ls -CF'
alias ltr='ls -ltr'

# BoGo alias-es-es
alias xcsel='xclip -sel clip'
alias ag="ag $* --hidden"
#
#         VISUAL is typically configured in the main .bashrc, per machine
alias v='$VISUAL'

export PATH="$PATH:$(dirname ${BASH_SOURCE[0]})"
