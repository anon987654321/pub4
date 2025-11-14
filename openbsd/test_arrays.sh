#!/usr/bin/env zsh
set -euo pipefail
readonly VERSION=337.5.0
readonly MAIN_IP=185.52.176.18

typeset -A all_domains
all_domains[brgen.no]="test"
all_domains[oshlo.no]="test"

print "Script syntax test passed"
for domain in ${(k)all_domains}; do
  print "Domain: $domain"
done
