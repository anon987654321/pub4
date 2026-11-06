# MASTER on a phone

MASTER runs on Android under Termux with the same soul.yml and laws.yml as desktop. Mobile readiness is measured locally; this is not a claim to scan or secure the whole Android operating system.

## Install

Use a maintained Termux build. The installer runs a fail-closed preflight before package operations: it requires Termux's expected PREFIX, refuses root, permits only the canonical HTTPS pub4 repository, keeps the install directory below Termux HOME, refuses symlink/non-Git collisions, and verifies the checkout origin and clean working tree before running project code.

    curl -fsSL https://raw.githubusercontent.com/anon987654321/pub4/main/MASTER/bin/master-mobile-install | sh

The installer no longer ignores doctor failures. Installation is considered successful only when `bin/master-mobile doctor` exits successfully. The doctor checks Ruby and dependencies, Termux detection, Falcon, canonical Git origin, clean tracked/index state, and private mobile state-directory permissions. It changes only the mobile state directory's mode to 0700.

Termux from F-Droid is the build that still receives updates. Install Termux:API from the same place if you want speech features; optional speech backends do not block installation.

## Provider sign-in

MASTER delegates sign-in to each provider's own CLI; it never copies OAuth tokens or session files into its own store. From the normal interactive prompt:

    /model auth
    /model auth login claude
    /model auth login chatgpt
    /model auth login grok

Claude uses its browser sign-in. On mobile or a headless terminal, Codex and Grok use their device-code flow when the installed CLI/account supports it. Use `--browser` to force the provider's regular browser flow, or `--device-auth` to request device code explicitly. `/model auth status` asks each provider CLI for its own status; installed is not reported as authenticated when the CLI cannot prove sign-in.

## Optional local model fallback

The local llama.cpp lane is a last resort, not a boot-time download. It appears only when both `llama-cli` and a readable GGUF file are present. Upstream documents building the CLI inside Termux; start with a modest context because large contexts can exhaust phone memory:

    pkg install git cmake libandroid-spawn
    git clone https://github.com/ggml-org/llama.cpp
    cd llama.cpp
    cmake -B build -DCMAKE_BUILD_TYPE=Release
    cmake --build build --config Release -j2
    export PATH="$HOME/llama.cpp/build/bin:$PATH"
    mkdir -p "$HOME/models"
    export MASTER_LLAMA_MODEL="$HOME/models/your-small-quantised-model.gguf"

Choose a quantised model that fits the phone's available memory and storage; MASTER does not download one or assume the device can run a particular size. The fallback starts with a 4096-token context and two CPU threads. Keep the model under Termux's private home directory for reliable file access. Restart MASTER after setting the environment variable, then inspect `/model list`. No local HTTP server or OpenAI-compatible endpoint is started.

## Use

`bin/master-mobile doctor` measures the phone and exits 0 only when required readiness and integrity checks pass. `bin/master-mobile bridge` serves the animated face at http://127.0.0.1:8765/face; open that URL in the phone browser while the bridge runs. The page uses one explicit listen press, then shows listening, thinking and speaking states. `bin/master-mobile host` runs the face socket alone. The bridge binds loopback because it has no authentication; do not forward port 8765 off the phone.

The normal Reline prompt also supports one deliberate microphone capture with `/listen`. It asks for both local grants before opening the microphone:

    /privacy grant microphone --confirm "GRANT microphone"
    /privacy grant speech_recognition --confirm "GRANT speech_recognition"

The same grants protect microphone capture in both the terminal and browser face, and expire after one hour. Grant them from the normal `bin/master` session before using the browser's listen button. Android still requires microphone permission for the Termux app, the Termux:API companion app, and `pkg install termux-api`. `/voice on` enables spoken replies in the terminal; the mobile browser bridge speaks each reply through Termux:API. Use the normal Termux app user, not a root/proot shell, so its API commands remain connected to the Android app.

## Security boundaries

MASTER runs as the Termux app user, not root. Root indicators and Android properties are heuristics or observations, not proof of device integrity. This mobile doctor checks the local MASTER checkout and its private state directory; it cannot attest that all Android apps or the operating system are malware-free. A clean `git diff` is not a cryptographic supply-chain attestation, and this installer currently follows the selected branch rather than a pinned signed release.
