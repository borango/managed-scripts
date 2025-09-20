#!/bin/bash

export SEARCHSTRING=$1

EXCLUDES="-p .ignore-for-replaces"

echo

ag -rc --hidden $EXCLUDES "$SEARCHSTRING" 2> /dev/null               # count and show colored output to user
ag -rl --hidden $EXCLUDES "$SEARCHSTRING" 2> /dev/null > _replace_in # save only filenames with search hits

echo "$SEARCHSTRING" > _replace_what

echo
echo "$SEARCHSTRING saved for replace_with <with-string>"
echo
