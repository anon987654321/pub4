# Ruby text-to-speech: A complete integration guide

Ruby developers have **robust options for TTS integration** despite the lack of native neural TTS engines in Ruby itself. The ecosystem splits between native gems like `espeak-ruby` for offline use, **official cloud SDKs** from Google and AWS for production quality, and subprocess patterns for accessing modern neural TTS engines like Piper and Coqui. For audio playback, the `audio-playback` gem provides cross-platform support, while system commands offer zero-dependency alternatives.

## Native Ruby TTS gems provide offline synthesis

The **espeak-ruby** gem stands as the most mature native TTS option, wrapping the espeak-ng engine with **752,000+ downloads** and active maintenance through 2022.

```ruby
# Installation: gem install espeak-ruby
# System deps: sudo apt install espeak lame (Linux)
require 'espeak'

# Direct speech output
ESpeak::Speech.new("Hello world").speak

# With voice customization
speech = ESpeak::Speech.new("Custom voice",
  voice: "en-us",    # 50+ languages
  pitch: 50,         # 0-99
  speed: 170,        # 80-370 WPM
  amplitude: 150     # 0-200
)
speech.speak
speech.save("output.mp3")  # Requires lame

# List available voices
ESpeak::Voice.all.each { |v| puts "#{v.language}: #{v.name}" }
```

The **tts** gem offers a simpler API using Google Translate's TTS service—useful for prototyping but **not suitable for production** due to reliance on undocumented APIs:

```ruby
# gem install tts
require 'tts'
"Hello World".to_file("en")  # Creates MP3
"Hello".play("en", 1)        # Direct playback
```

For SSML document generation, **ruby_speech** (101 GitHub stars, MIT licensed) creates standards-compliant markup for any TTS engine:

```ruby
# gem install ruby_speech
require 'ruby_speech'

ssml = RubySpeech::SSML.draw do
  voice gender: :male, name: 'fred' do
    string "Hello, the time is "
    say_as interpret_as: 'date', format: 'dmy' do "01/02/2025" end
  end
end
puts ssml.to_s  # Valid SSML XML
```

## Cloud APIs deliver production-quality neural voices

**Google Cloud TTS** offers the best official Ruby SDK with **875,000+ downloads**, supporting Neural2 and Studio voices across 380+ options in 75+ languages.

```ruby
# gem install google-cloud-text_to_speech
# Requires: GOOGLE_APPLICATION_CREDENTIALS env var
require "google/cloud/text_to_speech"

client = Google::Cloud::TextToSpeech.text_to_speech

response = client.synthesize_speech(
  input: { text: "Neural voice synthesis" },
  voice: { language_code: "en-US", name: "en-US-Neural2-D" },
  audio_config: { audio_encoding: :MP3 }
)

File.binwrite("output.mp3", response.audio_content)
```

**AWS Polly** provides similar quality through `aws-sdk-polly` with generous free tier (**5M characters/month** for 12 months):

```ruby
# gem install aws-sdk-polly
require 'aws-sdk-polly'

polly = Aws::Polly::Client.new(region: 'us-east-1')

response = polly.synthesize_speech(
  output_format: 'mp3',
  text: 'Neural voice from AWS',
  voice_id: 'Joanna',
  engine: 'neural'  # or 'generative' for latest
)

IO.copy_stream(response.audio_stream, 'output.mp3')
```

**OpenAI TTS** via the mature `ruby-openai` gem (**3.2k GitHub stars**) offers the simplest API with six high-quality voices:

```ruby
# gem install ruby-openai
require 'openai'

client = OpenAI::Client.new(access_token: ENV['OPENAI_API_KEY'])

response = client.audio.speech(
  parameters: {
    model: "tts-1-hd",        # or "tts-1" for faster
    input: "Hello from OpenAI",
    voice: "nova",            # alloy, echo, fable, onyx, nova, shimmer
    response_format: "mp3",
    speed: 1.0                # 0.25 to 4.0
  }
)

File.binwrite('output.mp3', response)
```

**ElevenLabs** delivers the highest voice quality through community gems like `elevenlabs-ruby`:

```ruby
# gem install elevenlabs-ruby
require 'elevenlabs-ruby'

ElevenLabs.configure { |c| c.api_key = ENV['ELEVENLABS_API_KEY'] }
client = ElevenLabs::Client.new

voices = client.get('voices')
voice_id = voices['voices'].first['voice_id']

audio = client.post("text-to-speech/#{voice_id}", {
  text: "Ultra-realistic voice",
  model_id: "eleven_monolingual_v1",
  voice_settings: { stability: 0.5, similarity_boost: 0.5 }
})

File.binwrite('output.mp3', audio)
```

### Cloud pricing comparison at a glance

| Service | Free Tier | Standard | Neural/HD |
|---------|-----------|----------|-----------|
| Google Cloud | 4M chars/mo | $4/1M | $16/1M |
| AWS Polly | 5M chars/mo (12mo) | $4/1M | $16/1M |
| Azure Speech | 500K chars/mo | — | $15/1M |
| OpenAI | None | $15/1M | $30/1M |
| ElevenLabs | 10K chars/mo | — | ~$300/1M |

## Windows SAPI integration through WIN32OLE

The **win32-sapi** gem wraps Microsoft's Speech API 5.x for native Windows TTS:

```ruby
# gem install win32-sapi
require 'win32/sapi5'
include Win32

v = SpVoice.new
v.Rate = 1      # -10 to 10
v.Volume = 80   # 0 to 100
v.Speak("Hello from SAPI")

# Async speech (non-blocking)
v.Speak("Background speech", SpVoice::SPF_ASYNC)
# Continue processing...
v.WaitUntilDone(-1)  # Wait when ready

# Voice selection
voices = v.GetVoices
0.upto(voices.Count - 1) do |n|
  v.Voice = voices.Item(n) if voices.Item(n).Id =~ /zira/i
end
```

Direct **WIN32OLE** access works without the gem, enabling file output:

```ruby
require 'win32ole'

voice = WIN32OLE.new('SAPI.SpVoice')
file_stream = WIN32OLE.new('SAPI.SpFileStream')
file_stream.Open("output.wav", 3)  # SSFMCreateForWrite
voice.AudioOutputStream = file_stream
voice.Speak("Saved to file")
file_stream.Close
```

**PowerShell integration** provides an alternative path using System.Speech:

```ruby
require 'open3'

def powershell_speak(text, voice: nil, rate: 0)
  script = <<~PS
    Add-Type -AssemblyName System.Speech
    $synth = New-Object System.Speech.Synthesis.SpeechSynthesizer
    $synth.Rate = #{rate}
    #{voice ? "$synth.SelectVoice('#{voice}')" : ''}
    $synth.Speak('#{text.gsub("'", "''")}')
  PS
  Open3.capture3("powershell", "-Command", script)
end

def powershell_save(text, path)
  script = <<~PS
    Add-Type -AssemblyName System.Speech
    $synth = New-Object System.Speech.Synthesis.SpeechSynthesizer
    $synth.SetOutputToWaveFile('#{path.gsub('/', '\\\\')}')
    $synth.Speak('#{text.gsub("'", "''")}')
  PS
  Open3.capture3("powershell", "-Command", script)
end
```

## Subprocess patterns unlock modern neural TTS

**Piper TTS** (fast, local, neural quality) has no Ruby gem but works excellently via subprocess:

```ruby
require 'open3'

class PiperTTS
  def initialize(model: "en_US-lessac-medium")
    @model = model
  end
  
  def synthesize(text, output: "output.wav")
    escaped = text.gsub('"', '\"')
    system("echo \"#{escaped}\" | piper --model #{@model} --output_file #{output}")
    output
  end
  
  # Stream to audio player (Linux)
  def speak(text)
    system("echo \"#{text}\" | piper --model #{@model} --output-raw | " \
           "aplay -r 22050 -f S16_LE -t raw -")
  end
end

piper = PiperTTS.new
piper.synthesize("Neural TTS from Piper")
```

**Coqui TTS** runs as an HTTP server that Ruby can call:

```ruby
# Start server: tts-server --model_name tts_models/en/ljspeech/tacotron2-DDC
require 'net/http'

class CoquiClient
  def initialize(url = "http://localhost:5002")
    @base_url = url
  end
  
  def synthesize(text, output: nil)
    uri = URI("#{@base_url}/api/tts")
    uri.query = URI.encode_www_form(text: text)
    audio = Net::HTTP.get(uri)
    output ? File.binwrite(output, audio) : audio
  end
end

CoquiClient.new.synthesize("Hello from Coqui", output: "output.wav")
```

**Edge-TTS** (Microsoft's free neural voices) requires Python but offers **unlimited free usage**:

```ruby
require 'open3'

class EdgeTTS
  def initialize(voice: "en-US-AriaNeural", rate: nil)
    @voice = voice
    @rate = rate
  end
  
  def synthesize(text, output:)
    args = ["edge-tts", "--voice", @voice, "--text", text, 
            "--write-media", output]
    args += ["--rate=#{@rate}"] if @rate
    Open3.capture3(*args)
    output
  end
  
  def self.voices
    `edge-tts --list-voices`
  end
end

EdgeTTS.new(voice: "en-US-GuyNeural", rate: "+10%")
        .synthesize("Free neural TTS", output: "output.mp3")
```

### Streaming with Open3 for real-time TTS

```ruby
require 'open3'

def stream_tts_to_player(text)
  Open3.popen3("espeak-ng", "--stdout", text) do |stdin, stdout, stderr, wait|
    stdin.close
    
    # Pipe directly to player
    IO.popen(["play", "-t", "wav", "-"], "wb") do |player|
      while (chunk = stdout.read(4096))
        player.write(chunk)
      end
    end
  end
end
```

## Audio playback options for Ruby applications

The **audio-playback** gem provides the best cross-platform solution with low latency:

```ruby
# gem install audio-playback
# Deps: brew install portaudio libsndfile (macOS)
#       apt install libportaudio19-dev libsndfile1-dev (Linux)
require "audio-playback"

# Blocking playback
AudioPlayback.play("output.wav").block

# Async with options
playback = AudioPlayback.play("output.wav", 
  latency: 0.1, 
  buffer_size: 4096
)
# Continue while playing...
```

**System commands** work without dependencies:

```ruby
# macOS
system("afplay", "output.wav")
spawn("afplay", "-v", "0.8", "output.wav")  # Async with volume

# Linux  
system("aplay", "output.wav")               # ALSA (WAV only)
system("play", "output.wav")                # SoX (all formats)
system("mpv", "--no-video", "output.mp3")   # mpv (all formats)

# Windows
system("powershell", "-c", 
       "(New-Object Media.SoundPlayer 'output.wav').PlaySync()")
```

The **wavefile** gem handles WAV processing in pure Ruby:

```ruby
# gem install wavefile
require 'wavefile'
include WaveFile

# Concatenate TTS chunks
Writer.new("combined.wav", Format.new(:mono, :pcm_16, 24000)) do |w|
  ["chunk1.wav", "chunk2.wav"].each do |f|
    Reader.new(f).each_buffer { |buf| w.write(buf) }
  end
end
```

### Continuous playback pattern for streaming TTS

```ruby
class ContinuousTTSPlayer
  def initialize
    @queue = Queue.new
    @running = false
  end
  
  def start
    @running = true
    @thread = Thread.new do
      while @running
        file = @queue.pop
        break if file == :stop
        system("play", "-q", file)
        File.delete(file) rescue nil
      end
    end
  end
  
  def enqueue(wav_file)
    @queue.push(wav_file)
  end
  
  def stop
    @running = false
    @queue.push(:stop)
    @thread&.join
  end
end

# Usage: generate TTS chunks while playing previous ones
player = ContinuousTTSPlayer.new
player.start

sentences.each_with_index do |text, i|
  path = "/tmp/chunk_#{i}.wav"
  piper.synthesize(text, output: path)
  player.enqueue(path)
end

player.stop
```

## Complete integration examples

### Background job pattern with Sidekiq

```ruby
class TTSJob
  include Sidekiq::Job
  sidekiq_options queue: 'tts', retry: 3
  
  def perform(text, output_path, options = {})
    case options['engine']
    when 'openai'
      client = OpenAI::Client.new
      audio = client.audio.speech(parameters: {
        model: "tts-1", input: text, voice: options['voice'] || 'nova'
      })
      File.binwrite(output_path, audio)
      
    when 'piper'
      system("echo \"#{text}\" | piper --model #{options['model']} " \
             "--output_file #{output_path}")
      
    when 'espeak'
      ESpeak::Speech.new(text, voice: options['voice']).save(output_path)
    end
  end
end
```

### Rails integration with Active Storage

```ruby
class ArticleAudioJob < ApplicationJob
  def perform(article)
    client = OpenAI::Client.new
    audio = client.audio.speech(parameters: {
      model: "tts-1-hd", input: article.content, voice: "nova"
    })
    
    article.audio.attach(
      io: StringIO.new(audio, 'rb'),
      filename: "article-#{article.id}.mp3",
      content_type: 'audio/mpeg'
    )
  end
end
```

## Conclusion

**For offline TTS**, espeak-ruby remains the go-to gem despite robotic voice quality. **For production applications**, Google Cloud TTS and AWS Polly offer the best balance of quality, pricing, and official SDK support. **For highest voice quality**, ElevenLabs leads but at premium cost.

The most practical approach for neural TTS combines **subprocess patterns with Piper** (local) or **edge-tts** (free cloud neural voices). Audio playback works best through the audio-playback gem or simple system commands to `play` (SoX). Threading and job queues enable continuous voice output—generate the next chunk while playing the current one.

Key recommendations by use case:
- **Prototype/hobby**: `tts` gem or edge-tts subprocess
- **Production app**: `google-cloud-text_to_speech` or `aws-sdk-polly`  
- **Offline requirement**: espeak-ruby (basic) or Piper subprocess (neural)
- **Windows desktop**: win32-sapi gem or WIN32OLE direct
- **Maximum quality**: ElevenLabs or OpenAI TTS