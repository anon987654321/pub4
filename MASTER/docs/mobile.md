# MASTER on a phone

MASTER runs on Android under Termux with the same soul.yml and laws.yml as desktop. Mobile readiness is measured locally; this is not a claim to scan or secure the whole Android operating system.

## Install

Use a maintained Termux build. The installer runs a fail-closed preflight before package operations: it requires Termux's expected PREFIX, refuses root, permits only the canonical HTTPS pub4 repository, keeps the install directory below Termux HOME, refuses symlink/non-Git collisions, and verifies the checkout origin and clean working tree before running project code.

    curl -fsSL https://raw.githubusercontent.com/anon987654321/pub4/main/MASTER/bin/master-mobile-install | sh

The installer no longer ignores doctor failures. Installation is considered successful only when `bin/master-mobile doctor` exits successfully. The doctor checks Ruby and dependencies, Termux detection, Falcon, canonical Git origin, clean tracked/index state, and private mobile state-directory permissions. It changes only the mobile state directory's mode to 0700.

Termux from F-Droid is the build that still receives updates. Install Termux:API from the same place if you want speech features; optional speech backends do not block installation.

## Use

`bin/master-mobile doctor` measures the phone and exits 0 only when required readiness and integrity checks pass. `bin/master-mobile bridge` serves the face at http://127.0.0.1:8765/face. `bin/master-mobile host` runs the face socket alone. The bridge binds loopback because it has no authentication; do not forward port 8765 off the phone.

## Security boundaries

MASTER runs as the Termux app user, not root. Root indicators and Android properties are heuristics or observations, not proof of device integrity. This mobile doctor checks the local MASTER checkout and its private state directory; it cannot attest that all Android apps or the operating system are malware-free. A clean `git diff` is not a cryptographic supply-chain attestation, and this installer currently follows the selected branch rather than a pinned signed release.
