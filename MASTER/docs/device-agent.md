# MASTER device agent

The Android/Termux device agent is the resident local loop behind the face.

It has four deliberately separate responsibilities:

- the face is interaction: terminal rendering, speech input and speech output;
- `Device::Agent` is cadence: one bounded resident tick and recovery from ordinary runtime errors;
- `Cognition::Mind` is persistent perception and reflection;
- `Ground::StandingOrders` is the durable objective ledger.

The agent never assumes that the person holding the phone is the owner. A fresh
phone is unpaired. The explicit command

    /pair owner [label]

creates the same scoped pairing identity used by the other MASTER channels,
stores its subject in `.master/device_agent.json`, creates that subject's
`.master/workspace/<subject>/USER.md` and `MEMORY.md`, and applies the identity
to the current session.

After that pairing survives the face worker threads: local turns use the
persisted subject when a Fiber-local subject is absent, and MemoryRecord writes
to that personal workspace. Standing orders run by the device agent are filtered
to the paired subject; operator-owned orders do not become phone automation by
accident.

`/device` reports whether the local companion is paired and when its resident
tick last ran.

## Interactive phone

A normal interactive boot starts the resident thread automatically on Android
unless `MASTER_DEVICE_AGENT=0`.

    bundle exec ruby bin/cli /face

This keeps the face and resident agent in the same process. Closing the face
also ends that process.

## Resident service

For an agent that survives closing the face, run the standalone launcher under
the process supervisor of your choice:

    bundle exec ruby bin/device-agent

The launcher disables the web server and TTS service for that resident process,
boots the same MASTER runtime and keeps `Device::Agent#run_forever` in the
foreground. Termux:API, whisper.cpp setup and the normal Android capability
checks remain part of the same boot surface.

A process supervisor should restart the launcher after process death. The
device agent itself does not grant Android permissions, install arbitrary apps,
or execute owner orders before explicit pairing.

## Ownership boundary

Pairing is consent, not identity inference.

Before `/pair owner`, MASTER may observe its own runtime and device capability
events so Cognition can maintain local system continuity. It does not treat
those observations as facts about a human owner and does not run owner-scoped
standing orders.

After `/pair owner`, the subject is a durable local identity. The owner profile
is still bounded: personal memory and objectives live under the subject, while
operator capabilities remain governed by MASTER's existing Tool::Profile and
Tool::Domain boundaries.

The architecture therefore is:

    Android
      |
      +-- Termux process supervisor
      |     |
      |     +-- MASTER boot
      |           +-- Device::Setup
      |           +-- Device::Perception
      |           +-- Cognition::Mind
      |           +-- Device::Agent
      |                 +-- personal StandingOrders
      |                 +-- personal USER.md / MEMORY.md
      |
      +-- /face  <- interaction surface

This is a local personal-agent architecture, not device takeover. Android
remains the authority over permissions and process lifetime.
