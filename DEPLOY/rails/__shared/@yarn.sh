#!/bin/zsh

if ! command_exists yarn; then
  echo "Yarn is not installed. Installing..."
  doas pkg_add -U node
  doas npm install yarn -g
fi

