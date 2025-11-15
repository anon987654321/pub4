#!/usr/bin/env zsh
cd /home/brgen/app
cp Gemfile Gemfile.bak
awk 'BEGIN{print "ruby \"3.3.7\""} !/^ruby /{print}' Gemfile.bak > Gemfile
print "Fixed Gemfile ruby version"
