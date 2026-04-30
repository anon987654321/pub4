# Real-time audio streaming for TTS pipelines: zero-file architectures

Direct audio streaming from text-to-speech engines to speakers—bypassing intermediate files entirely—is achievable through a combination of Unix pipes, sox/ffmpeg streaming, and careful buffer management. **The core pattern is remarkably simple**: `espeak --stdout "text" | sox -t wav - -d` streams synthesized speech directly to output. This report details the complete toolkit for building low-latency audio pipelines with real-time effects processing.

The key architectural insight is that modern TTS engines like espeak-ng and Piper output to stdout natively, while sox and ffmpeg can both read from stdin and write to audio devices. Ruby integration works best through `IO.popen` and `Open3.popen3` for bidirectional streaming, with pure Ruby DSP possible via the `wavefile` and `ffi-portaudio` gems. Latency under **50ms** is achievable with buffer sizes of 2048-4096 bytes on ALSA, though PulseAudio adds 10-50ms overhead.

## Sox streaming delivers the simplest real-time pipeline

Sox provides the most straightforward path from TTS to speakers. The `-` special filename reads from stdin (requiring `-t TYPE` format specification), while `-d` outputs to the default audio device.

**Complete TTS-to-speakers pipeline:**
```bash
espeak --stdout "Hello world" | sox -t wav - -d
# Or with play command (equivalent)
espeak --stdout "Hello" | play -t wav -
```

**Raw PCM input** requires explicit format specification:
```bash
piper --output-raw | sox -t raw -r 22050 -b 16 -c 1 -e signed - -d
```

The key format options: `-r` (sample rate), `-b` (bit depth), `-c` (channels), `-e` (encoding: signed-integer, unsigned-integer, floating-point). For little-endian systems, add `-L`.

**Real-time effects during playback** chain directly after the output device:
```bash
espeak --stdout "Robotic voice" | sox -t wav - -d \
    lowpass 3000 overdrive 10 reverb 30
```

Lofi effect chains for audio character:
```bash
play input.wav lowpass 4000 gain -2 overdrive 5 \
    echo 0.8 0.88 6 0.4 reverb 20
```

**Buffer size optimization** uses `--buffer BYTES` (default 8192). For low latency:
```bash
sox --buffer 4096 -t wav - -d   # ~90ms latency at 44100Hz stereo
sox --buffer 2048 -t wav - -d   # ~45ms latency, higher CPU
```

Latency formula: `latency_ms ≈ (buffer_bytes / (sample_rate × bytes_per_sample × channels)) × 1000`

**Platform-specific output devices:**
| Platform | Command |
|----------|---------|
| Linux ALSA | `sox input.wav -t alsa default` |
| Linux PulseAudio | `sox input.wav -t pulseaudio` |
| macOS | `sox input.wav -t coreaudio` |
| Windows | `sox input.wav -t waveaudio` |

Environment variables `AUDIODRIVER` and `AUDIODEV` configure defaults.

## FFmpeg enables advanced filtering and multi-stream mixing

FFmpeg provides more sophisticated audio filtering and handles MP3/AAC streams that TTS engines like edge-tts produce.

**Low-latency configuration flags** minimize startup and processing delay:
```bash
ffmpeg -fflags nobuffer -flags low_delay \
       -probesize 32 -analyzeduration 0 \
       -f s16le -ar 22050 -ac 1 -i pipe:0 \
       -f pulse "TTS Output"
```

Key flags: `-fflags nobuffer` (disable input buffering), `-flags low_delay` (minimize codec buffering), `-thread_queue_size 512` (prevent blocking with real-time sources).

**Reading raw PCM from stdin:**
```bash
tts_generator | ffmpeg -f s16le -ar 24000 -ac 1 -i pipe:0 -f alsa default
```

Common raw formats: `s16le` (16-bit signed little-endian), `f32le` (32-bit float), `u8` (unsigned 8-bit).

**Real-time audio filters** apply during streaming with `-af`:
```bash
ffmpeg -i input.mp3 -af "highpass=f=80,lowpass=f=10000,acompressor=threshold=0.1:ratio=4,volume=1.2" -f alsa default
```

The `acrusher` filter creates lo-fi bitcrushing: `acrusher=bits=8:mix=0.5:samples=4`

**Mixing multiple streams** uses the `amix` filter:
```bash
ffmpeg -i voice.wav -f lavfi -i "anoisesrc=c=pink:a=0.02:d=30" \
       -filter_complex "[0:a][1:a]amix=inputs=2:duration=first:weights=1 0.1" \
       -f pulse output
```

**Generated audio via lavfi** creates background noise without files:
```bash
# Play brown noise
ffplay -f lavfi -i "anoisesrc=c=brown:a=0.1:d=60"

# Sine wave generation
ffmpeg -f lavfi -i "sine=frequency=440:duration=5" -f alsa default
```

## TTS engines with native stdout streaming

**espeak/espeak-ng** outputs WAV to stdout at 22050Hz, 16-bit mono:
```bash
espeak-ng --stdout -v en-us -s 150 "Hello" | play -t wav -
```

Options: `-s` (speed 80-370 WPM), `-p` (pitch 0-99), `-a` (amplitude 0-200).

**Piper TTS** streams raw PCM with `--output-raw`:
```bash
echo "Low latency speech" | piper --model en_US-amy-medium.onnx --output-raw | \
    aplay -r 22050 -f S16_LE -t raw -
```

Piper achieves neural TTS quality with faster-than-realtime synthesis on Raspberry Pi 4.

**edge-tts** (Microsoft neural voices) streams MP3 chunks via Python API:
```python
import edge_tts
import asyncio

async def stream():
    communicate = edge_tts.Communicate("Hello", "en-US-EmmaNeural")
    async for chunk in communicate.stream():
        if chunk["type"] == "audio":
            yield chunk["data"]  # MP3 bytes, pipe to ffmpeg
```

**nanotts** (enhanced pico2wave) supports stdout:
```bash
echo "Hello" | nanotts -c | play -r 16k -L -t raw -e signed -b 16 -c 1 -
```

**flite** offers minimal latency (<25ms startup):
```bash
flite -t "Hello world"  # Direct playback
```

| Engine | Sample Rate | Format | Latency | Quality |
|--------|-------------|--------|---------|---------|
| espeak-ng | 22050 Hz | WAV | <50ms | Formant |
| Piper | 22050 Hz | Raw PCM | ~100ms | Neural |
| edge-tts | 24000 Hz | MP3 | ~200ms | Neural |
| flite | 8000 Hz | WAV | <25ms | Basic |

## Unix pipes and named FIFOs enable complex routing

**Standard pipes** connect TTS to effects to output:
```bash
espeak --stdout "text" | sox -t wav - -t wav - gain -3 | play -t wav -
```

The `-p` flag is shorthand for `-t sox -` enabling seamless multi-stage piping:
```bash
sox input.wav -p reverb | sox -p -p chorus | sox -p output.wav flanger
```

**Named pipes (FIFOs)** allow multiple producers and persistent connections:
```bash
mkfifo /tmp/audio_pipe
trap "rm -f /tmp/audio_pipe" EXIT

# Reader (runs in background)
cat /tmp/audio_pipe | play -t wav - &

# Writer
espeak --stdout "Message" > /tmp/audio_pipe
```

**Process substitution** (`<()` syntax) treats command output as files:
```bash
sox -m <(sox tts.wav -t wav -) <(sox background.wav -t wav -) -t wav - | play -
```

**Mixing multiple sources** with FFmpeg and named pipes:
```bash
mkfifo /tmp/voice /tmp/background
ffmpeg -i /tmp/voice -i /tmp/background \
    -filter_complex "amix=inputs=2:weights=1 0.15" -f alsa default &
espeak --stdout "Speech" > /tmp/voice &
sox -n -t wav - synth 5 brownnoise > /tmp/background &
```

**Buffer management** for low latency uses `stdbuf`:
```bash
stdbuf -o0 audio_generator | stdbuf -i0 sox -t raw ... - -d
```

## Ruby integration patterns for streaming audio

**IO.popen for unidirectional streaming:**
```ruby
# Capture TTS output
audio = IO.popen(['espeak', '--stdout', 'Hello'], 'rb', &:read)

# Stream to player
IO.popen(['aplay', '-r', '22050', '-f', 'S16_LE', '-t', 'raw'], 'wb') do |io|
  samples.each_slice(1024) { |chunk| io.write(chunk.pack('s*')) }
end
```

**Open3.popen3 for bidirectional pipes:**
```ruby
require 'open3'

Open3.popen3('sox', '-t', 'raw', '-r', '22050', '-b', '16', '-e', 'signed', 
             '-c', '1', '-', '-t', 'raw', '-', 'reverb', '50') do |stdin, stdout, stderr, wait|
  Thread.new { stdin.write(pcm_data); stdin.close }
  Thread.new { process_output(stdout.read) }
  wait.value
end
```

**Open3.pipeline_rw for multi-stage pipelines:**
```ruby
Open3.pipeline_rw(
  ['ruby', '-e', 'generate_audio'],
  ['sox', '-t', 'raw', '-r', '22050', '-b', '16', '-e', 'signed', '-c', '1', '-', '-d']
) do |first_stdin, last_stdout, threads|
  first_stdin.write(text)
  first_stdin.close
end
```

**Signal handling for cleanup:**
```ruby
pids = []
at_exit { pids.each { |p| Process.kill('TERM', p) rescue nil } }
Signal.trap('INT') { pids.each { |p| Process.kill('TERM', p) rescue nil }; exit }
```

## Ruby-native audio processing without shelling out

**wavefile gem** (pure Ruby) handles WAV I/O:
```ruby
require 'wavefile'
include WaveFile

# Generate sine wave
samples = (0...44100).map { |i| 0.5 * Math.sin(2 * Math::PI * 440 * i / 44100.0) }
buffer = Buffer.new(samples, Format.new(:mono, :float, 44100))
Writer.new("output.wav", Format.new(:mono, :pcm_16, 44100)) { |w| w.write(buffer) }
```

**ffi-portaudio** provides real-time audio I/O:
```ruby
require 'ffi-portaudio'

callback = lambda do |input, output, frame_count, time_info, status, user_data|
  # Process samples in real-time
  :paContinue
end
```

**easy_audio** simplifies PortAudio usage:
```ruby
require 'easy_audio'
EasyAudio.easy_open(&EasyAudio::Waveforms::SINE)
sleep 2
```

**Pure Ruby audio effects:**
```ruby
# Bitcrushing
def bitcrush(samples, bits)
  max_val = (2 ** bits) - 1
  samples.map do |s|
    normalized = (s + 1.0) / 2.0
    quantized = (normalized * max_val).round / max_val.to_f
    (quantized * 2.0) - 1.0
  end
end

# Simple lowpass filter
def lowpass(samples, cutoff, sample_rate)
  rc = 1.0 / (2.0 * Math::PI * cutoff)
  alpha = (1.0 / sample_rate) / (rc + 1.0 / sample_rate)
  prev = 0.0
  samples.map { |s| prev = prev + alpha * (s - prev) }
end

# Soft clipping/saturation
def soft_clip(samples, threshold = 0.7)
  samples.map do |s|
    s.abs < threshold ? s : (s <=> 0) * (threshold + (1 - threshold) * 
      Math.tanh((s.abs - threshold) / (1 - threshold)))
  end
end
```

**win32-sound** for Windows playback (limited to WAV files):
```ruby
require 'win32/sound'
Win32::Sound.play("file.wav")
Win32::Sound.play_freq(440, 1000)  # 440Hz for 1 second
```

## Windows and Cygwin audio output configuration

**Sox on Windows** uses `-t waveaudio`:
```bash
sox input.wav -t waveaudio
sox input.wav -t waveaudio 0  # Device by index
espeak --stdout "Hello" | sox -t wav - -t waveaudio
```

Device enumeration: `sox.exe -V6 -n -t waveaudio invalidname` lists available devices.

**Cygwin audio** requires PulseAudio:
```bash
# Install: apt-cyg install pulseaudio
# Configure default.pa:
load-module module-native-protocol-tcp auth-ip-acl=127.0.0.1
load-module module-waveout sink_name=output

# In Cygwin shell:
export PULSE_SERVER=tcp:localhost
sox input.wav -t pulseaudio
```

**WSL2 audio** forwards to Windows PulseAudio:
```bash
# WSLg (Windows 11) works automatically
# WSL2 (Windows 10) needs manual setup:
export PULSE_SERVER=tcp:$(cat /etc/resolv.conf | grep nameserver | awk '{print $2}')
```

**FFmpeg Windows output:**
```bash
# DirectShow (capture)
ffmpeg -f dshow -audio_buffer_size 50 -i audio="Microphone" output.wav

# SDL playback
set SDL_AUDIODRIVER=directsound
ffplay -nodisp input.mp3
```

Windows latency hierarchy: WDM-KS (~1-5ms) < WASAPI Exclusive (~3-10ms) < WASAPI Shared (~10ms+) < DirectSound (~40ms+) < WaveOut (~100ms+).

## Complete working pipeline examples

**TTS with lofi effects (no files):**
```bash
espeak --stdout "Welcome to the system" | \
    sox -t wav - -d lowpass 3000 overdrive 8 reverb 40 gain -3
```

**Background noise mixed with speech:**
```bash
#!/bin/bash
mkfifo /tmp/tts /tmp/noise
trap "rm -f /tmp/tts /tmp/noise" EXIT

ffmpeg -f wav -i /tmp/tts -f wav -i /tmp/noise \
    -filter_complex "amix=inputs=2:weights=1 0.15:duration=first" \
    -f alsa default &

espeak --stdout "Hello with ambient background" > /tmp/tts &
sox -n -t wav - synth 5 brownnoise vol 0.3 > /tmp/noise &
wait
```

**Ruby streaming TTS pipeline:**
```ruby
require 'open3'

def speak_with_effects(text, effects = 'reverb 30')
  Open3.pipeline(
    ['espeak', '--stdout', text],
    ['sox', '-t', 'wav', '-', '-d'] + effects.split
  )
end

speak_with_effects("Real-time audio processing", "lowpass 4000 overdrive 5 reverb 25")
```

**Continuous vinyl crackle generator:**
```bash
sox -n -t raw -r 44100 -b 16 -c 2 - synth brownnoise \
    band -n 1500 300 tremolo 0.03 40 reverb 20 | \
    sox -t raw -r 44100 -b 16 -c 2 - -d
```

## Conclusion

Building zero-file TTS audio pipelines requires understanding three key components: **TTS stdout output** (espeak-ng, Piper), **streaming audio processors** (sox `-` and ffmpeg `pipe:0`), and **Ruby process management** (IO.popen, Open3). The simplest working pipeline—`espeak --stdout | sox -t wav - -d`—serves as the foundation for arbitrarily complex effect chains.

For Ruby applications, the pattern of spawning sox/ffmpeg subprocesses with stdin/stdout piping outperforms pure Ruby audio processing for real-time effects, while gems like `wavefile` and `ffi-portaudio` enable in-process audio manipulation when needed. On Windows, sox's `-t waveaudio` driver provides the cleanest integration, while Cygwin and WSL require PulseAudio bridging with measurable latency overhead.

The critical latency optimization is buffer sizing—**2048-4096 bytes** achieves sub-50ms latency on direct ALSA output, while PulseAudio's default 2-second buffers require explicit `PULSE_LATENCY_MSEC` configuration. For neural TTS like Piper, the synthesis latency (100-200ms) typically exceeds the audio pipeline latency, making aggressive buffer tuning less impactful than engine selection.