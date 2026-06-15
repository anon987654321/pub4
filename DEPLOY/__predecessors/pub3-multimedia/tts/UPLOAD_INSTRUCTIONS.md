# Upload Instructions for Malaysian Voice System
## Backup File Location
**Full path:** `/data/data/com.termux/files/home/malay_voice_final_YYYYMMDD_HHMMSS.tar.gz`
## File Services to Upload To
### Option 1: Transfer.sh (Quick & Easy)
```bash

curl --upload-file ~/malay_voice_final_*.tar.gz https://transfer.sh/malay_voice.tar.gz

```

Returns a download URL valid for 14 days.

### Option 2: 0x0.st (Simple)
```bash

curl -F'file=@'~/malay_voice_final_*.tar.gz https://0x0.st

```

Returns a download URL.

### Option 3: File.io (One-time download)
```bash

curl -F "file=@"~/malay_voice_final_*.tar.gz https://file.io

```

URL expires after first download.

### Option 4: Termux Storage Access (Copy to SD card)
```bash

# First enable storage

termux-setup-storage

# Copy to Downloads folder
cp ~/malay_voice_final_*.tar.gz ~/storage/downloads/

```

Then upload from phone's Downloads folder to any cloud service.

### Option 5: Send to Pastebin/GitHub Gist (for code only)
For sharing just the Ruby scripts:

```bash

# Install termux-api first

pkg install termux-api

# Copy file path to clipboard
termux-clipboard-set < ~/malay_voice_final_*.tar.gz

```

## What's Included in Backup
- `comfy_tts.rb` - Core TTS engine with male voice
- `voice_effects.rb` - Sox effects library

- `malay_funny.rb` - Malaysian comedy (20 jokes)

- `malay_bedtime.rb` - Bedtime stories

- `.bashrc` - Configuration

- `VOICE_SYSTEM_SETUP.md` - Complete documentation

- `CLAUDE_PROMPTS.md` - All prompts used

- `install_voice_system.sh` - Installation script

## To Restore on New Device
1. Extract archive:
```bash

cd ~

tar -xzf malay_voice_final_*.tar.gz

```

2. Run installer:
```bash

bash install_voice_system.sh

```

3. Start voice:
```bash

ruby malay_funny.rb

```

## Voice Settings (for reference)
**Malaysian Male Voice:**
- TTS: gTTS with Indian accent (co.in)

- Pitch: -120 (deep male)

- Speed: 0.92 (slow, steady)

- Bass: +5

- Effects: Chorus, compression

**Quick test:**
```bash

ruby -r ./comfy_tts -e "ComfyTTS.setup; ComfyTTS.speak('Testing Malaysian male voice', speed: 0.92, pitch_adjust: -120, accent: 'in')"

```

## File Size
Approximately 47KB (compressed)

## System Requirements
- Termux on Android

- Python 3.12+

- Ruby

- Sox

- play-audio

- gTTS (pip)

All automatically installed by setup script.
---
Generated: 2025-10-16

Claude Code + Master.json v336.1.0

