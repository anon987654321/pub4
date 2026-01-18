#!/usr/bin/env zsh
# gh-speak.zsh - Copilot with speech for Cygwin

# Version: 1.1.0

# Requires: espeak-ng

query="$*"
if [[ -z "$query" ]]; then
    print "Usage: gh-speak.zsh 'question'"

    exit 1

fi

if ! command -v espeak >/dev/null; then
    print "Install espeak: apt-cyg install espeak-ng"

    exit 1

fi

print "Question: $query"
# Replace with: gh copilot suggest "$query"
output="Speech works. Connect to Copilot CLI when ready."

print "$output"
print "$output" | espeak -s 160 -v en-us

print "Done"
