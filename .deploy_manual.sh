#!/usr/bin/env zsh
# Manual deployment script for brgen.no infrastructure
# Run this on your local machine to deploy to OpenBSD VPS

set -euo pipefail

readonly VPS_IP="185.206.147.27"
readonly VPS_USER="dev"
readonly VPS_PASS="tata1234"

print "=== Brgen.no Deployment ==="
print "VPS: ${VPS_USER}@${VPS_IP}"
print ""

# Step 1: Push local changes
print "1. Pushing changes to GitHub..."
cd ~/pub
git add -A
git commit -m "Deployment $(date +%Y-%m-%d_%H:%M:%S)" || true
git push origin main

# Step 2: SSH and deploy
print "2. SSHing to VPS (password: ${VPS_PASS})..."
ssh -o StrictHostKeyChecking=no ${VPS_USER}@${VPS_IP} << 'ENDSSH'
set -euo pipefail

# Clean and clone
cd /home/dev
rm -rf pub4
git clone https://github.com/anon987654321/pub4.git
cd pub4

# Phase 1: Infrastructure (requires doas/root)
print "\n=== Phase 1: OpenBSD Infrastructure Setup ==="
doas zsh openbsd/openbsd.sh --pre-point

print "\n=== Waiting 60s for DNS propagation ==="
sleep 60

# Phase 2: TLS + Proxy
print "\n=== Phase 2: TLS Certificates & Reverse Proxy ==="
doas zsh openbsd/openbsd.sh --post-point

# Phase 3: Rails Apps
print "\n=== Phase 3: Deploying Rails Apps ==="
cd rails

for app in brgen brgen_marketplace brgen_playlist brgen_dating brgen_tv brgen_takeaway amber blognet bsdports hjerterom privcam pub_attorney baibl; do
  print "\n--- Deploying ${app} ---"
  zsh ${app}.sh || print "ERROR: ${app} failed"
done

print "\n=== Deployment Complete ==="
print "Sites:"
print "  https://brgen.no"
print "  https://playlist.brgen.no"
print "  https://dating.brgen.no"
print "  https://tv.brgen.no"
print "  https://takeaway.brgen.no"
print "  https://markedsplass.brgen.no"
print "  https://amberapp.com"
print "  + 40 more domains"
ENDSSH

print "\n✅ All done!"
