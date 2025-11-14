# MB-Sound Setup Instructions

## Status
- ✅ Repository cloned to `mb-sound/`
- ✅ Soundfonts directory restored
- ✅ Jnsgm2.sf2 soundfont present
- ⚠️  Gem dependencies not yet installed

## To Complete Setup

### 1. Install System Dependencies (Cygwin)
```bash
# Install libsamplerate development files
apt-cyg install libsamplerate-devel

# Or via Cygwin setup.exe, search for:
# - libsamplerate-devel
# - ffmpeg (already available)
```

### 2. Install Ruby Dependencies
```bash
cd G:\pub4\multimedia\dilla\mb-sound

# Install gems
bundle install

# Compile C extensions
rake compile
```

### 3. Test Installation
```ruby
# In dilla.rb, the line should work:
require "mb-sound"
MB_SOUND_AVAILABLE = true
```

## Current Behavior
Dilla.rb **works WITHOUT mb-sound** - it's an optional enhancement:
- Uses SoX for all audio generation ✅
- Professor Crane TTS works ✅
- Pad/Drum/Bass synthesis works ✅
- mb-sound would add advanced features if installed

## What mb-sound Adds
- Real-time audio synthesis DSL
- Advanced FM/AM synthesis
- Interactive sound playground (`bin/sound.rb`)
- More synthesis algorithms

## If Setup Fails
Dilla will continue to function with SoX-only synthesis (current mode).
