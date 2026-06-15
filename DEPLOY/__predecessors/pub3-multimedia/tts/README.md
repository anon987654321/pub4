# TTS - Multi-Engine Text-to-Speech System

Professional text-to-speech system with multiple engines, AI integration, and multi-language support.

## Overview

The TTS subsystem provides a unified interface to multiple speech synthesis engines with intelligent engine selection, Claude AI integration for narration, and specialized scripts for different use cases.

## Quick Start

```bash
# Basic usage
ruby smart_say.rb "Hello, world!"

# AI narration
ruby claude_speak.rb

# Install engines
./install_voice_system.sh

# Background speech
./background_talk.sh "Working on task"
```

## Supported Engines

| Engine | Type | Quality | Latency | Offline | Best For |
|--------|------|---------|---------|---------|----------|
| **Piper** | Neural TTS | High | Low | ✅ | General purpose |
| **Sherpa-ONNX** | Neural TTS | High | Very Low | ✅ | Real-time |
| **gTTS** | Cloud API | Medium | Medium | ❌ | Simple tasks |
| **Replicate** | AI Voice | Very High | High | ❌ | Professional audio |
| **System** | OS Native | Varies | Low | ✅ | Fallback |

## Installation

### Quick Install (All Engines)
```bash
./install_voice_system.sh
```

This script installs:
- Piper TTS
- Sherpa-ONNX
- Ruby gems (tty-prompt, http)
- System dependencies

### Manual Installation

**Piper TTS:**
```bash
ruby install_piper.rb
# Or manually:
# wget https://github.com/rhasspy/piper/releases/download/v1.2.0/piper_linux_x86_64.tar.gz
# tar xzf piper_linux_x86_64.tar.gz
```

**Sherpa-ONNX:**
```bash
ruby install_sherpa.rb
```

**Ruby Gems:**
```bash
gem install tty-prompt http json fileutils
```

**System TTS (macOS):**
```bash
# Already available via `say` command
```

**System TTS (Linux):**
```bash
sudo apt install espeak-ng  # or
sudo apt install festival
```

## Core Scripts

### smart_say.rb - Intelligent Engine Selection

**Purpose:** Main entry point with automatic engine selection.

**Features:**
- Detects available engines
- Selects best engine for context
- Fallback chain if engine unavailable
- Voice customization

**Usage:**
```bash
ruby smart_say.rb "Text to speak"
ruby smart_say.rb -v female "Text with female voice"
ruby smart_say.rb -e piper "Force Piper engine"
```

**Engine Selection Logic:**
1. Replicate (if API key available, for professional quality)
2. Piper (if installed, for high quality)
3. Sherpa-ONNX (if installed, for low latency)
4. gTTS (if online, for simplicity)
5. System TTS (always available, for fallback)

### claude_speak.rb - AI Narrator

**Purpose:** Claude AI integration for intelligent narration.

**Features:**
- Natural conversation flow
- Context-aware responses
- Automatic speech synthesis
- Interactive mode

**Usage:**
```bash
# Interactive mode
ruby claude_speak.rb

# Single utterance
ruby claude_speak.rb "Explain quantum computing"

# From file
ruby claude_speak.rb < script.txt
```

**Configuration:**
Set environment variable:
```bash
export ANTHROPIC_API_KEY="your-api-key"
```

### narrate_reasoning.rb - Reasoning Narrator

**Purpose:** Narrate step-by-step reasoning processes.

**Features:**
- Structured reasoning output
- Pause between steps
- Emphasis on key points
- Progress indication

**Usage:**
```bash
ruby narrate_reasoning.rb "Problem: Calculate factorial of 5"
```

**Output Example:**
```
Step 1: Understanding the problem...
[SPEECH: "First, we need to understand what factorial means"]

Step 2: Breaking down the calculation...
[SPEECH: "Factorial of 5 is 5 times 4 times 3 times 2 times 1"]

Step 3: Computing the result...
[SPEECH: "The answer is 120"]
```

## Specialized Scripts

### Multi-Language Support

**malay_funny.rb** - Malay humor and casual speech
```bash
ruby malay_funny.rb "Lawak"
```

**bomoh_hangtuah.rb** - Historical/cultural Malay narration
```bash
ruby bomoh_hangtuah.rb "Cerita lama"
```

### Automation Scripts

**background_talk.sh** - Background speech without blocking
```bash
./background_talk.sh "Processing files" &
```

**speak.sh** - Simple wrapper for system TTS
```bash
./speak.sh "Quick announcement"
```

**enable_mic.sh** - Enable microphone for speech input
```bash
./enable_mic.sh
```

### Claude Integration Variants

**claude_auto_speak.rb** - Automatic continuous narration
```bash
ruby claude_auto_speak.rb input.txt
```

**claude_continuous.rb** - Continuous conversation loop
```bash
ruby claude_continuous.rb
```

**claude_voice.rb** - Voice-specific Claude integration
```bash
ruby claude_voice.rb --voice alloy
```

### Engine-Specific Scripts

**tts.rb** - Direct TTS engine wrapper
```bash
ruby tts.rb piper "Text to speak"
```

**ruby_tts.rb** - Pure Ruby TTS implementation
```bash
ruby ruby_tts.rb "Text to speak"
```

**gtts_ruby.rb** - Google TTS via Ruby
```bash
ruby gtts_ruby.rb "Text to speak"
```

**comfy_tts.rb** - ComfyUI TTS integration
```bash
ruby comfy_tts.rb "Text to speak"
```

## Windows Support

**say.bat** - Windows batch script
```cmd
say.bat "Text to speak"
```

**read_master.ps1** - PowerShell script for reading files
```powershell
.\read_master.ps1 -File input.txt
```

## Configuration

### Engine Priority

Edit `smart_say.rb` to adjust engine priority:
```ruby
ENGINES = %w[replicate piper sherpa gtts system]
```

### Voice Selection

**Piper voices:**
```bash
# List available voices
piper --list-voices

# Use specific voice
ruby smart_say.rb -v en_US-lessac-medium "Text"
```

**System voices (macOS):**
```bash
# List voices
say -v ?

# Use specific voice
say -v Alex "Text"
```

### API Configuration

**Replicate:**
```bash
export REPLICATE_API_TOKEN="your-token"
```

**Claude:**
```bash
export ANTHROPIC_API_KEY="your-key"
```

**Google Cloud (gTTS):**
```bash
# No API key needed for basic gTTS
# For Cloud TTS API:
export GOOGLE_APPLICATION_CREDENTIALS="path/to/credentials.json"
```

## Integration with Other Subsystems

### With Repligen (AI Images)
```bash
# Generate image description
cd ../repligen
ruby repligen.rb "portrait" > description.txt

# Narrate description
cd ../tts
ruby claude_speak.rb < ../repligen/description.txt
```

### With Dilla (Music)
```bash
# Describe music generation
cd ../dilla
echo "Generating algorithmic composition" | \
  tee >(cd ../tts && ruby smart_say.rb)
```

### With Postpro (Images)
```bash
# Narrate processing steps
cd ../postpro
ruby postpro.rb --verbose input.jpg 2>&1 | \
  grep "Step" | \
  xargs -I {} ruby ../tts/smart_say.rb {}
```

## Output Formats

**Supported formats:**
- WAV (44.1kHz, 16-bit, mono/stereo)
- MP3 (128-320kbps)
- OGG (configurable bitrate)

**Default output:** `output/speech_YYYYMMDD_HHMMSS.wav`

All output is gitignored (`multimedia/tts/output/`, `*.wav`, `*.mp3`).

## Troubleshooting

### Piper Issues

**Problem:** `piper: command not found`
**Solution:** Run `ruby install_piper.rb` or add to PATH

**Problem:** `No voice models found`
**Solution:** Download voice models:
```bash
wget https://github.com/rhasspy/piper/releases/download/v1.2.0/voice-en-us-lessac-medium.onnx
```

### Sherpa-ONNX Issues

**Problem:** `sherpa-onnx not found`
**Solution:** Run `ruby install_sherpa.rb`

**Problem:** `Segmentation fault`
**Solution:** Reinstall with correct architecture:
```bash
ruby install_sherpa.rb --arch $(uname -m)
```

### gTTS Issues

**Problem:** `Network unreachable`
**Solution:** Check internet connection, gTTS requires online access

**Problem:** `Rate limit exceeded`
**Solution:** Add delays between requests or switch to Piper

### Claude Issues

**Problem:** `ANTHROPIC_API_KEY not set`
**Solution:** Export API key:
```bash
export ANTHROPIC_API_KEY="sk-ant-..."
```

**Problem:** `Rate limit exceeded`
**Solution:** Add cooldown between requests

### Audio Issues

**Problem:** No sound output
**Solution:** Check audio device:
```bash
# macOS
system_profiler SPAudioDataType

# Linux
aplay -l
pactl list sinks
```

**Problem:** Distorted audio
**Solution:** Adjust sample rate/bitrate in engine config

## Advanced Usage

### Batch Processing
```bash
# Process multiple files
for file in *.txt; do
  ruby smart_say.rb "$(cat "$file")" \
    --output "output/$(basename "$file" .txt).wav"
done
```

### Voice Cloning (Replicate)
```bash
ruby smart_say.rb \
  --engine replicate \
  --voice-sample my_voice.wav \
  "Text to speak in my voice"
```

### SSML Support (Advanced)
```ruby
# In smart_say.rb
text = <<~SSML
  <speak>
    <prosody rate="slow" pitch="+2st">
      Hello, world!
    </prosody>
  </speak>
SSML
```

### Custom Voice Filters
```bash
# Apply effects with sox
ruby smart_say.rb "Text" --output temp.wav
sox temp.wav output.wav reverb 50 50 100
```

## Performance

**Benchmarks (approximate):**
- Piper: 1-2s for 100 words
- Sherpa-ONNX: 0.5-1s for 100 words (real-time capable)
- gTTS: 2-5s for 100 words (depends on network)
- Replicate: 5-15s for 100 words (high quality)
- System TTS: 1-3s for 100 words

**Recommendations:**
- Real-time applications: Sherpa-ONNX
- Batch processing: Piper
- Cloud applications: gTTS or Replicate
- Offline/embedded: Piper or System TTS

## Development

### Adding New Engines

1. Create engine wrapper in `lib/engines/`:
```ruby
# lib/engines/my_engine.rb
class MyEngine
  def self.speak(text, options = {})
    # Implementation
  end
end
```

2. Register in `smart_say.rb`:
```ruby
ENGINES[:my_engine] = MyEngine
```

3. Add installation script if needed:
```ruby
# install_my_engine.rb
```

### Testing
```bash
# Test all engines
for engine in piper sherpa gtts system; do
  ruby smart_say.rb -e "$engine" "Testing $engine"
done

# Test Claude integration
ruby claude_speak.rb <<< "Test question"
```

## Documentation Files

This subsystem includes several documentation files:

- **README.md** (this file) - Main documentation
- **CLAUDE_PROMPTS.md** - Claude AI integration prompts
- **UPLOAD_INSTRUCTIONS.md** - Guide for uploading audio
- **voice_scripts_guide.md** - Overview of all voice scripts
- **android_autostart_guide.txt** - Android automation setup

## API Reference

### smart_say.rb
```
Usage: ruby smart_say.rb [OPTIONS] TEXT

Options:
  -e, --engine ENGINE    Force specific engine
  -v, --voice VOICE      Select voice
  -o, --output FILE      Save to file
  -q, --quiet            Suppress output
  --list-engines         Show available engines
  --list-voices          Show available voices
```

### claude_speak.rb
```
Usage: ruby claude_speak.rb [TEXT]

Interactive mode: No arguments
Single shot: Provide text as argument
Piped input: cat file.txt | ruby claude_speak.rb
```

## Contributing

When adding new scripts:
1. Follow Ruby 3.3+ standards
2. Include error handling
3. Support offline fallbacks
4. Add to this README
5. Test with all engines

## Links

- **Piper TTS:** https://github.com/rhasspy/piper
- **Sherpa-ONNX:** https://github.com/k2-fsa/sherpa-onnx
- **gTTS:** https://gtts.readthedocs.io/
- **Replicate:** https://replicate.com/
- **Claude AI:** https://www.anthropic.com/

---

For system-wide multimedia documentation, see [multimedia/README.md](../README.md).
