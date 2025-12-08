#!/usr/bin/env zsh
# DNS verification before post-point deployment
# Checks if domains resolve to VPS IP

readonly VPS_IP="185.52.176.18"
readonly TEST_DOMAINS=(
  "brgen.no"
  "oshlo.no"
  "trndheim.no"
  "bsdports.org"
  "amberapp.com"
)

print "Checking DNS propagation to $VPS_IP..."
print ""

typeset -i passed=0
typeset -i failed=0

for domain in $TEST_DOMAINS; do
  result=$(dig +short "$domain" @8.8.8.8 2>/dev/null | head -1)
  
  if [[ "$result" == "$VPS_IP" ]]; then
    print "✓ $domain → $result"
    ((passed++))
  else
    print "✗ $domain → ${result:-NO_RESPONSE} (expected $VPS_IP)"
    ((failed++))
  fi
done

print ""
print "Results: $passed passed, $failed failed"
print ""

if [[ $failed -eq 0 ]]; then
  print "✓ DNS fully propagated - ready for: doas zsh openbsd.sh --post-point"
  exit 0
else
  print "✗ DNS not fully propagated yet - wait 24-48h after glue record update"
  print "  Check status: dig brgen.no @8.8.8.8"
  exit 1
fi
