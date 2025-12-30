# XTTS-v2 Installation Guide for Windows
# Created: 2025-12-30

## Problem: Python 3.13 Incompatibility

XTTS-v2 (Coqui TTS) requires **Python 3.9-3.11**, but system has Python 3.13.
This is a common issue with cutting-edge TTS engines.

## Solution Options

### Option 1: Python Virtual Environment with 3.11

```powershell
# Install pyenv-win for multiple Python versions
winget install pyenv

# Or use Conda
conda create -n tts python=3.11
conda activate tts
pip install TTS

# Test XTTS-v2
tts --text "Hello world" --model_name tts_models/multilingual/multi-dataset/xtts_v2 --out_path output.wav
```

### Option 2: Docker Container (Recommended for Production)

```powershell
# Pull XTTS-v2 Docker image
docker pull ghcr.io/coqui-ai/tts

# Run with GPU support
docker run --gpus all -it -p 5002:5002 ghcr.io/coqui-ai/tts --model_name tts_models/multilingual/multi-dataset/xtts_v2
```

### Option 3: XTTS API Server (Easiest)

```powershell
# Clone and run community API server
git clone https://github.com/daswer123/xtts-api-server
cd xtts-api-server
docker-compose up
```

Then use REST API:
```powershell
curl -X POST http://localhost:8020/tts `
  -H "Content-Type: application/json" `
  -d '{"text": "Hello world", "language": "en", "speaker_wav": "reference.wav"}'
```

### Option 4: Alternative Engines (Already Working)

**Current Setup (Working Now):**
- ✅ **SAPI** (Windows built-in) - Clean, instant
- ✅ **pyttsx3** (Python SAPI wrapper) - Installed and tested
- ✅ **FFmpeg audio processing** - 1.8x faster lofi chains

**Recommended Alternatives to XTTS-v2:**

#### 1. **Piper** (Best XTTS alternative)
- Quality: Neural, high quality
- Latency: 100-150ms
- License: MIT (commercial friendly)
- VRAM: 2GB
- Languages: 30+

```powershell
# Download from GitHub releases
Invoke-WebRequest -Uri "https://github.com/rhasspy/piper/releases/download/v1.2.0/piper_windows_amd64.zip" -OutFile piper.zip
Expand-Archive piper.zip -DestinationPath G:\pub\tts\piper

# Download voice model
Invoke-WebRequest -Uri "https://huggingface.co/rhasspy/piper-voices/resolve/main/en/en_US/lessac/medium/en_US-lessac-medium.onnx" -OutFile model.onnx

# Test
.\piper.exe --model model.onnx --output_file test.wav < input.txt
```

#### 2. **Sherpa-ONNX (Kokoro-82M)**
- Quality: Very high
- Latency: 50-150ms
- License: Apache 2.0
- VRAM: 2GB
- Voices: 12 (American, British accents)

```powershell
# Download from GitHub
Invoke-WebRequest -Uri "https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/kokoro-v0_19.tar.bz2" -OutFile kokoro.tar.bz2
```

#### 3. **Edge-TTS** (Cloud, Free)
- Quality: Excellent (Microsoft Neural)
- Latency: 200ms + network
- License: Free (unofficial API)
- Voices: 400+

```powershell
pip install edge-tts
edge-tts --voice en-US-AriaNeural --text "Hello world" --write-media output.mp3
```

## PowerShell Integration

### Current Working Solution (pyttsx3)

```powershell
function Invoke-PythonTTS {
    param([string]$Text, [int]$Rate = 0)
    
    $script = @"
import pyttsx3
engine = pyttsx3.init()
engine.setProperty('rate', 150 + ($Rate * 10))
engine.say('$Text')
engine.runAndWait()
"@
    
    py -c $script
}

# Usage
Invoke-PythonTTS "Hello from Python TTS"
```

### Edge-TTS Integration

```powershell
function Invoke-EdgeTTS {
    param([string]$Text, [string]$Voice = "en-US-AriaNeural")
    
    $outputFile = [System.IO.Path]::GetTempFileName() -replace '\.tmp$', '.mp3'
    
    & edge-tts --voice $Voice --text $Text --write-media $outputFile
    Start-Process $outputFile -Wait
    Remove-Item $outputFile -Force
}

# Usage
Invoke-EdgeTTS "Neural cloud TTS with Microsoft voice"
```

## Recommendation for Your System

**Skip XTTS-v2 for now.** Here's why:

1. **Python 3.13 incompatibility** - Would need separate Python environment
2. **4GB VRAM requirement** - Check GPU availability first
3. **Complex dependencies** - PyTorch, CUDA, ffmpeg
4. **Non-commercial license** - Coqui Public License restricts use

**Better alternatives already working:**

✅ **Current Setup** (SAPI + FFmpeg lofi) - Works perfectly, instant
✅ **pyttsx3** - Python integration if needed
✅ **Edge-TTS** - `pip install edge-tts` for 400+ neural voices

**If you need XTTS-v2 features (voice cloning):**
- Use **Piper** (MIT license, works on Python 3.13)
- Use **OpenVoice V2** (MIT, best commercial voice cloning)
- Set up **Python 3.11 virtual environment** specifically for XTTS-v2

## Testing Current System

```powershell
# Load TTS config
. "$HOME\Documents\PowerShell\TTS\tts_config.ps1"

# Test clean voice
say "Testing clean SAPI voice"

# Test lofi presets
lofi "Testing vintage lofi preset" -Preset vintage

# Test bomoh character
bomoh "Testing mystical voice" -WithEffects

# Test funny voices
funny "Testing helium voice" -Voice helium
```

## Performance Comparison

| Engine | Latency | Quality | License | Python Ver |
|--------|---------|---------|---------|-----------|
| **SAPI (Current)** | Instant | Medium | Free | Any |
| **pyttsx3** | Instant | Medium | MPL-2.0 | 3.13 ✅ |
| **Edge-TTS** | 200ms | Excellent | Free | 3.13 ✅ |
| **Piper** | 100ms | High | MIT | 3.13 ✅ |
| **XTTS-v2** | 150ms | Excellent | Non-comm | 3.9-3.11 ❌ |
| **Kokoro** | 150ms | Very High | Apache | 3.13 ✅ |

## Conclusion

**Your current setup is production-ready.** XTTS-v2 would be overkill for your use case. 

If you want better quality later, install **Edge-TTS** (one command) or **Piper** (MIT licensed, commercial-friendly).
