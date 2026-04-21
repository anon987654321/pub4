# Disable host‑key checking only when you trust the network.
# Prefer a dedicated SSH key pair and configure it in ~/.ssh/config
# rather than embedding passwords in scripts.

set -euo pipefail

ssh -i ~/.ssh/id_rsa_brgen \
    -o StrictHostKeyChecking=no \
    dev@brgen.no \
    -- 'cmd'