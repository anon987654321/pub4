#!/bin/zsh
set -euo pipefail
# Deploy to OpenBSD VPS
ssh -i G:/priv/passwd/id_rsa dev@185.162.251.62 << 'ENDSSH'
cd /home/dev
rm -rf pub4
git clone https://github.com/anon987654321/pub4.git
cd pub4
doas sh openbsd/openbsd.sh
ENDSSH
print "✅ Deployment complete - https://brgen.no should be live!"
