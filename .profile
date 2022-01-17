# ~/.profile: executed by the command interpreter for login shells.
# This file is not read by bash(1), if ~/.bash_profile or ~/.bash_login
# exists.
# see /usr/share/doc/bash/examples/startup-files for examples.
# the files are located in the bash-doc package.

# the default umask is set in /etc/profile; for setting the umask
# for ssh logins, install and configure the libpam-umask package.
#umask 022

# if running bash
if [ -n "$BASH_VERSION" ]; then
    # include .bashrc if it exists
    if [ -f "$HOME/.bashrc" ]; then
          . "$HOME/.bashrc"
    fi
fi

# set PATH so it includes user's private bin if it exists
if [ -d "$HOME/bin" ] ; then
   PATH="$HOME/bin:$PATH"
fi

# set PATH so it includes user's private bin if it exists
if [ -d "$HOME/.local/bin" ] ; then
   PATH="$HOME/.local/bin:$PATH"
fi

if [ -d "$HOME/kts-jira-extract-transform/sh" ] ; then
   PATH="$HOME/kts-jira-extract-transform/sh:$PATH"
fi

if [     -d "$HOME/garmin-connect-iq-sdk/connectiq-sdk-lin-3.1.6-2019-10-23-2de4665c6/bin" ] ; then
 PATH="$PATH:$HOME/garmin-connect-iq-sdk/connectiq-sdk-lin-3.1.6-2019-10-23-2de4665c6/bin"
fi
