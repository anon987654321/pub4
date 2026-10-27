# MASTER on a phone

MASTER runs on an Android phone under Termux with the same soul.yml and
laws.yml it answers to on the desktop. The phone runs less of it: no
background scan, no desktop web face, no OpenBSD host tools, no STUDIO
rendering. What it adds is a face you can talk to on the phone itself.

## Install

A fresh Termux has `sh` and `pkg` and nothing else, so the installer is the
one shell script in MASTER. It installs Ruby, git and the build tools that
Bundler needs for native gems, clones pub4, installs Falcon into the phone's
Ruby and runs the doctor.

    curl -fsSL https://raw.githubusercontent.com/anon987654321/pub4/main/MASTER/bin/master-mobile-install | sh

Termux from F-Droid is the build that still receives updates. Install
Termux:API from the same place if you want to speak to MASTER rather than
type; the doctor reports whether speech-to-text and text-to-speech are
present and does not block without them.

## Use

`bin/master-mobile doctor` measures the phone and exits 0 only when it is
ready. `bin/master-mobile bridge` serves the face at
http://127.0.0.1:8765/face. `bin/master-mobile host` runs the face socket
alone, for a companion app that speaks the socket protocol. Anything else is
passed to `bin/master` in the mobile profile.

The bridge binds loopback because it has no authentication. Do not forward
port 8765 off the phone.

## What runs where

Master::Mobile::Profile switches the profile on when Termux is detected or
MASTER_PROFILE=mobile is set, and sets the environment defaults in
data/mobile.yml. At boot, before Bundler builds a gem, Master::Mobile::Bootstrap
installs any missing required package through `pkg`, wrapped in the same
before-and-after effect envelope the Fold uses, so a package list never
reaches the audit stream, only its digest. MASTER_MOBILE_AUTO_APPROVE=0 makes
it ask instead.

Each utterance goes to `bin/master -m` as a child process, with the person's
remembered preferences and the last eight turns ahead of it. The session
(.master/mobile/session.json) keeps forty turns so a reconnecting face picks
the conversation up. Listening happens only while the listen button is
pressed for one utterance; there is no background capture, and no audio is
kept.

## The face socket

A companion connects to .master/mobile/face.sock (mode 0600) and exchanges
one JSON object per line. It sends hello, ping, utterance (text, source),
listen_start, listen_stop and cancel. MASTER answers hello_ok
(protocol_version, run_id, profile, modes), pong, state (mode, listening,
summary), face (expression, attention), say (text) after an utterance, and
error (code, message) for a type it does not know. The modes are the desktop
face's: idle, listening, thinking, working, speaking, warning, error, sleeping
and ready. The socket holds a Termux wake lock while it is open.

An Android launcher that opens the face full screen is not built. It would be
a WebView on http://127.0.0.1:8765/face that starts `bin/master-mobile bridge`
through Termux's RUN_COMMAND intent; until then, a browser tab on that address
does the same job.
