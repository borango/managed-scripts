#!/bin/bash

export SEARCHSTRING=$1

EXCLUDES="--ignore _replace_in --ignore replace.sh --ignore .storage/core.restore_state"

echo

ag -rFc --hidden $EXCLUDES "$SEARCHSTRING" 2> /dev/null               # count and show colored output to user
ag -rFl --hidden $EXCLUDES "$SEARCHSTRING" 2> /dev/null > _replace_in # save only filenames with search hits

echo "$SEARCHSTRING" > _replace_what

echo
echo "$SEARCHSTRING saved for replace_with <with-string>"
