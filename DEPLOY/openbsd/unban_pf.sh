#!/usr/bin/env zsh
# unban_pf.sh — clear pf <bruteforce> table on vm23 when direct SSH is blocked.
# Run from your workstation (has the dev key).
#
# Per openbsd.amsterdam/onboard.html + our pf.conf:
#   table <bruteforce> persist
#   block quick from <bruteforce>
#   ... overload <bruteforce> flush global on port 22/80/443
#
# Strategy: SSH to hypervisor (same key, port 31415), attach console,
#           run pfctl inside the VM, then ~. to detach.
#
# Usage:
#   zsh DEPLOY/openbsd/unban_pf.sh
#   (or after: ssh dev@46.23.89.226 to verify)
#
# Exit console: ~.
# Requires: your ~/.ssh/id_ed25519_brgen (or equivalent) works for host+VM.

set -euo pipefail

HOST="server4.openbsd.amsterdam"
PORT=31415
KEY=${KEY:-~/.ssh/id_ed25519_brgen}
VM="vm23"

echo "Connecting to hypervisor host for console access (OpenBSD Amsterdam)..."
echo "Host: $HOST:$PORT  VM: $VM"
echo "Key: $KEY"
echo

# Non-interactive-ish: ssh to host then immediately vmctl console.
# Inside the cu(1) console you will get the VM login prompt.
# Login (root or dev), then:
#   doas pfctl -t bruteforce -T flush
#   pfctl -t bruteforce -T show
# Detach with ~. (tilde dot) after the flush succeeds.
ssh -p "$PORT" -i "$KEY" \
    -o StrictHostKeyChecking=accept-new \
    -o VerifyHostKeyDNS=yes \
    dev@"$HOST" "vmctl console $VM"

echo
echo "After ~. exit, test direct:"
echo "  ssh -i $KEY dev@46.23.89.226"
echo
echo "If still blocked, re-run and do the pfctl inside the console."
echo "Docs: https://openbsd.amsterdam/onboard.html (console section)"
