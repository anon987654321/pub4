# frozen_string_literal: true

# TTS Plugins - Consolidated TTS Backend Implementations
#
# This file consolidates three TTS backend implementations into a single plugin:
#   - TTS: Replicate cloud API (minimax/speech-02-turbo) - high quality, costs money
#   - PiperTTS: Local neural TTS - fast, free, offline capable with voice effects
#   - EdgeTTS: Microsoft Edge cloud API - free, 400+ voices, no API key required
#   - ParallelTTS: Parallel audio generation variant of TTS
#
# Each backend provides different tradeoffs between quality, cost, latency, and features.

require 'net/http'
require 'json'
require 'uri'
require 'open3'
require 'fileutils'
require 'securerandom'

module MASTER
  # TTS: Cloud-based TTS using Replicate's minimax/speech-02-turbo model
  # NOTE: This is one of three TTS implementations:
  #   - TTS (this file): Replicate cloud API - high quality, costs money
  #   - PiperTTS: Local neural TTS - fast, free, offline capable
  #   - EdgeTTS: Microsoft cloud - free, 400+ voices, no API key
  class TTS
    REPLICATE_TOKEN = ENV['REPLICATE_API_TOKEN']
    MODEL = 'minimax/speech-02-turbo'
    VOICE = 'Casual_Guy'
    MAX_PARALLEL = 3
    POLL_INTERVAL = 0.5
    MAX_POLLS = 60

    def initialize
      @queue = Queue.new
      @mutex = Mutex.new
      @playing = false
      @worker = nil
    end

    def speak(text)
      return unless REPLICATE_TOKEN
      return if text.nil? || text.strip.empty?

      chunks = split_into_chunks(text)
      chunks.each { |chunk| @queue.push(chunk) }
      start_worker unless @worker&.alive?
    end

    def speaking?
      @playing || !@queue.empty?
    end

    def stop
      @queue.clear
      @playing = false
    end

    private

    def start_worker
      @worker = Thread.new do
        while (chunk = @queue.pop(true) rescue nil) || !@queue.empty?
          break unless chunk
          audio_url = generate_audio(chunk)
          play_audio(audio_url) if audio_url
        end
      end
    end

    def split_into_chunks(text, max_chars: 200)
      # Split on sentence boundaries for natural TTS
      sentences = text.split(/(?<=[.!?])\s+/)
      chunks = []
      current = ""

      sentences.each do |sentence|
        if (current + " " + sentence).length > max_chars
          chunks << current.strip unless current.empty?
          current = sentence
        else
          current = current.empty? ? sentence : "#{current} #{sentence}"
        end
      end
      chunks << current.strip unless current.empty?
      chunks
    end

    def generate_audio(text)
      uri = URI("https://api.replicate.com/v1/models/#{MODEL}/predictions")
      
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      http.open_timeout = 10
      http.read_timeout = 30

      request = Net::HTTP::Post.new(uri)
      request['Authorization'] = "Bearer #{REPLICATE_TOKEN}"
      request['Content-Type'] = 'application/json'
      request['Prefer'] = 'wait'

      request.body = {
        input: {
          text: text,
          voice_id: VOICE,
          speed: 1.0
        }
      }.to_json

      response = http.request(request)
      data = JSON.parse(response.body)

      # If immediate result
      return data['output'] if data['output']

      # Otherwise poll for completion
      poll_for_result(data['urls']['get']) if data.dig('urls', 'get')
    rescue => e
      nil
    end

    def poll_for_result(url)
      uri = URI(url)
      MAX_POLLS.times do
        sleep POLL_INTERVAL

        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true

        request = Net::HTTP::Get.new(uri)
        request['Authorization'] = "Bearer #{REPLICATE_TOKEN}"

        response = http.request(request)
        data = JSON.parse(response.body)

        case data['status']
        when 'succeeded'
          return data['output']
        when 'failed', 'canceled'
          return nil
        end
      end
      nil
    end

    def play_audio(url)
      return unless url
      @mutex.synchronize { @playing = true }

      begin
        # Download to temp file
        uri = URI(url)
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = uri.scheme == 'https'
        
        response = http.get(uri.request_uri)
        return unless response.is_a?(Net::HTTPSuccess)

        temp = File.join(Dir.tmpdir, "master_tts_#{SecureRandom.hex(4)}.wav")
        File.binwrite(temp, response.body)

        # Play based on platform
        case RUBY_PLATFORM
        when /openbsd/
          system("aucat -i #{temp}")
        when /darwin/
          system("afplay #{temp}")
        when /linux/
          system("aplay -q #{temp} 2>/dev/null || paplay #{temp} 2>/dev/null")
        when /mingw|mswin/
          # Windows: use PowerShell
          system("powershell -c \"(New-Object Media.SoundPlayer '#{temp}').PlaySync()\"")
        end

        File.delete(temp) rescue nil
      ensure
        @mutex.synchronize { @playing = false }
      end
    end
  end

  # Parallel TTS generator - generates multiple chunks simultaneously
  class ParallelTTS < TTS
    def speak(text)
      return unless REPLICATE_TOKEN
      return if text.nil? || text.strip.empty?

      chunks = split_into_chunks(text)
      return if chunks.empty?

      # Generate all audio in parallel
      audio_urls = parallel_generate(chunks)

      # Play sequentially
      audio_urls.compact.each { |url| play_audio(url) }
    end

    private

    def parallel_generate(chunks)
      threads = chunks.first(MAX_PARALLEL).map.with_index do |chunk, i|
        Thread.new { [i, generate_audio(chunk)] }
      end

      results = threads.map(&:value).sort_by(&:first).map(&:last)

      # Generate remaining chunks if any
      if chunks.size > MAX_PARALLEL
        chunks[MAX_PARALLEL..].each do |chunk|
          results << generate_audio(chunk)
        end
      end

      results
    end
  end

  # PiperTTS: Local neural TTS using Piper - fast, free, no API needed
  # Supports voice manipulation: speed, pitch, emotion via noise_scale
  class PiperTTS
    VOICES_DIR = File.join(Paths.var, 'piper_voices')
    DEFAULT_VOICE = 'en_US-lessac-medium'

    # Voice presets - personality through parameters
    # length_scale: <1.0 = fast/high, >1.0 = slow/deep
    # noise_scale:  <0.3 = flat/robotic, >0.7 = unstable/emotional
    PRESETS = {
      normal:     { length_scale: 1.0,  noise_scale: 0.667 },
      chipmunk:   { length_scale: 0.6,  noise_scale: 0.667 },  # Fast, high pitched
      zombie:     { length_scale: 2.5,  noise_scale: 0.4 },    # Slow, deep, flat
      robot:      { length_scale: 1.0,  noise_scale: 0.1 },    # Monotone GPS voice
      manic:      { length_scale: 0.8,  noise_scale: 0.9 },    # Unstable, drunk
      calm:       { length_scale: 1.2,  noise_scale: 0.3 },    # Slow, steady, soothing
      urgent:     { length_scale: 0.7,  noise_scale: 0.5 },    # Fast, focused, news anchor
      whisper:    { length_scale: 1.3,  noise_scale: 0.2 },    # Soft, flat, ASMR
      excited:    { length_scale: 0.75, noise_scale: 0.8 },    # Fast, variable, hyped
      depressed:  { length_scale: 1.4,  noise_scale: 0.1 },    # Slow, flat, sad
      demon:      { length_scale: 3.0,  noise_scale: 0.3 },    # Very slow, deep
      caffeinated:{ length_scale: 0.5,  noise_scale: 0.7 }     # Hyperfast, jittery
    }.freeze

    # Text effects - manipulate input for glitch/stutter/robotic feel
    TEXT_EFFECTS = {
      stutter:    ->(t) { t.gsub(/\b(\w)/, '\1-\1-\1') },                    # H-H-Hello
      glitch:     ->(t) { t.chars.map { |c| rand < 0.1 ? "#{c}#{c}#{c}" : c }.join },
      spaces:     ->(t) { t.chars.join(' ') },                               # H e l l o
      slow_spell: ->(t) { t.gsub(/(\w)/, '\1... ') },                        # H... e... l...
      robotic:    ->(t) { t.upcase.gsub(/[.,!?]/, '. BEEP. ') },             # HELLO. BEEP.
      whisper:    ->(t) { t.downcase.gsub(/[!]/, '...') },                   # hello...
      dramatic:   ->(t) { t.gsub(/(\w+)/) { |w| "#{w}..." } },               # Hello... world...
      corrupt:    ->(t) { t.chars.map { |c| rand < 0.05 ? %w[# @ $ %].sample : c }.join }
    }.freeze

    attr_reader :voice, :preset

    def initialize(voice: DEFAULT_VOICE, preset: :normal)
      @voice = voice
      @preset = preset
      @params = PRESETS[preset] || PRESETS[:normal]
      @queue = Queue.new
      @playing = false
      @worker = nil
      ensure_voice_installed
    end

    def speak(text, preset: nil, effect: nil)
      return if text.nil? || text.strip.empty?

      @params = PRESETS[preset] if preset && PRESETS[preset]
      text = apply_effect(text, effect) if effect

      chunks = split_sentences(text)
      chunks.each { |c| @queue.push(c) }
      start_worker unless @worker&.alive?
    end

    def speak_sync(text, preset: nil, effect: nil)
      return nil if text.nil? || text.strip.empty?

      @params = PRESETS[preset] if preset && PRESETS[preset]
      text = apply_effect(text, effect) if effect
      generate_and_play(text)
    end

    # Generate audio file without playing - for web streaming
    def generate(text, output: nil, preset: nil, effect: nil)
      return nil if text.nil? || text.strip.empty?

      @params = PRESETS[preset] if preset && PRESETS[preset]
      text = apply_effect(text, effect) if effect
      output ||= temp_wav
      generate_audio(text, output)
      output
    end

    # Generate base64 audio for web embedding
    def generate_base64(text, preset: nil, effect: nil)
      file = generate(text, preset: preset, effect: effect)
      return nil unless file && File.exist?(file)

      require 'base64'
      data = Base64.strict_encode64(File.binread(file))
      File.delete(file) rescue nil
      "data:audio/wav;base64,#{data}"
    end

    # Apply text effect for glitch/stutter/robotic speech
    def apply_effect(text, effect)
      transform = TEXT_EFFECTS[effect.to_sym]
      transform ? transform.call(text) : text
    end

    def speaking?
      @playing || !@queue.empty?
    end

    def stop
      @queue.clear
      @playing = false
    end

    def set_preset(name)
      @preset = name
      @params = PRESETS[name] || PRESETS[:normal]
    end

    private

    def start_worker
      @worker = Thread.new do
        while (chunk = @queue.pop(true) rescue nil)
          generate_and_play(chunk)
        end
      end
    end

    def generate_and_play(text)
      @playing = true
      output = temp_wav
      
      if generate_audio(text, output)
        play_audio(output)
      end
      
      File.delete(output) rescue nil
      @playing = false
    end

    def generate_audio(text, output)
      model = voice_path
      return false unless File.exist?(model)

      cmd = build_command(text, model, output)
      system(cmd)
      File.exist?(output) && File.size(output) > 0
    end

    def build_command(text, model, output)
      escaped = text.gsub('"', '\\"').gsub('`', '\\`')
      length = @params[:length_scale]
      noise = @params[:noise_scale]

      case RUBY_PLATFORM
      when /openbsd|linux|darwin/
        "echo \"#{escaped}\" | piper --model #{model} --output_file #{output} --length_scale #{length} --noise_scale #{noise} 2>/dev/null"
      when /mingw|mswin/
        "echo #{escaped} | py -m piper --model #{model} --output #{output} --length_scale #{length} --noise_scale #{noise}"
      else
        "echo \"#{escaped}\" | piper --model #{model} --output_file #{output}"
      end
    end

    def play_audio(file)
      return unless File.exist?(file)

      case RUBY_PLATFORM
      when /openbsd/
        system("aucat -i #{file} 2>/dev/null")
      when /darwin/
        system("afplay #{file}")
      when /linux/
        system("aplay -q #{file} 2>/dev/null || paplay #{file} 2>/dev/null || mpv --no-video #{file} 2>/dev/null")
      when /mingw|mswin/
        system("powershell -c \"(New-Object Media.SoundPlayer '#{file}').PlaySync()\"")
      end
    end

    def split_sentences(text, max: 300)
      sentences = text.split(/(?<=[.!?])\s+/)
      chunks = []
      current = ""

      sentences.each do |s|
        if (current.length + s.length) > max
          chunks << current.strip unless current.empty?
          current = s
        else
          current = current.empty? ? s : "#{current} #{s}"
        end
      end
      chunks << current.strip unless current.empty?
      chunks
    end

    def voice_path
      File.join(VOICES_DIR, "#{@voice}.onnx")
    end

    def temp_wav
      File.join(Dir.tmpdir, "piper_#{SecureRandom.hex(4)}.wav")
    end

    def ensure_voice_installed
      FileUtils.mkdir_p(VOICES_DIR)
      return if File.exist?(voice_path)

      # Auto-download voice on first use
      Dmesg.log("piper0", message: "downloading #{@voice}...") rescue nil
      download_voice(@voice)
    end

    def download_voice(name)
      base = "https://huggingface.co/rhasspy/piper-voices/resolve/main/en/en_US/lessac/medium"
      
      %w[.onnx .onnx.json].each do |ext|
        url = "#{base}/en_US-lessac-medium#{ext}"
        out = File.join(VOICES_DIR, "#{name}#{ext}")
        
        case RUBY_PLATFORM
        when /openbsd/
          system("ftp -o #{out} #{url} 2>/dev/null")
        else
          system("curl -sL #{url} -o #{out}")
        end
      end
    end
  end

  # EdgeTTS: Free unlimited Microsoft neural voices via edge-tts Python package
  # Zero cost, 400+ voices, 150ms latency, no API key needed
  class EdgeTTS
    OUTPUT_DIR = File.join(MASTER::Paths.var, 'edge_tts')

    # Popular voices - neural quality, many languages
    VOICES = {
      # English US
      aria:      'en-US-AriaNeural',        # Female, warm
      guy:       'en-US-GuyNeural',         # Male, casual
      jenny:     'en-US-JennyNeural',       # Female, friendly
      davis:     'en-US-DavisNeural',       # Male, authoritative
      # English UK
      sonia:     'en-GB-SoniaNeural',       # Female, British
      ryan:      'en-GB-RyanNeural',        # Male, British
      # Norwegian
      finn:      'nb-NO-FinnNeural',        # Male, Norwegian
      pernille:  'nb-NO-PernilleNeural',    # Female, Norwegian
      iselin:    'nb-NO-IselinNeural',      # Female, Norwegian
      # Other languages
      seraphina: 'de-DE-SeraphinaMultilingualNeural',  # German female
      vivienne:  'fr-FR-VivienneMultilingualNeural',   # French female
      florian:   'de-DE-FlorianMultilingualNeural'     # German male
    }.freeze

    # Pitch/rate adjustments (edge-tts uses +/-Hz and +/-%)
    STYLES = {
      normal:    { rate: '+0%',  pitch: '+0Hz' },
      fast:      { rate: '+25%', pitch: '+0Hz' },
      slow:      { rate: '-20%', pitch: '+0Hz' },
      high:      { rate: '+0%',  pitch: '+50Hz' },
      low:       { rate: '+0%',  pitch: '-50Hz' },
      excited:   { rate: '+15%', pitch: '+30Hz' },
      calm:      { rate: '-10%', pitch: '-20Hz' },
      whisper:   { rate: '-15%', pitch: '-30Hz' },
      urgent:    { rate: '+30%', pitch: '+20Hz' }
    }.freeze

    class << self
      def installed?
        system('python -c "import edge_tts" 2>/dev/null') ||
          system('python3 -c "import edge_tts" 2>/dev/null') ||
          system('py -c "import edge_tts" 2>/dev/null')
      end

      def install!
        python = %w[py python3 python].find { |p| system("#{p} --version > /dev/null 2>&1") }
        system("#{python} -m pip install edge-tts --quiet")
      end

      # Generate audio file
      def generate(text, voice: :aria, style: :normal, output: nil)
        return nil if text.nil? || text.strip.empty?

        FileUtils.mkdir_p(OUTPUT_DIR)
        output ||= File.join(OUTPUT_DIR, "edge_#{SecureRandom.hex(4)}.mp3")

        voice_id = VOICES[voice.to_sym] || VOICES[:aria]
        params = STYLES[style.to_sym] || STYLES[:normal]

        python = %w[py python3 python].find { |p| system("#{p} --version > /dev/null 2>&1") }
        
        script = <<~PY
          import asyncio
          import edge_tts
          async def main():
              communicate = edge_tts.Communicate(
                  #{text.inspect},
                  voice="#{voice_id}",
                  rate="#{params[:rate]}",
                  pitch="#{params[:pitch]}"
              )
              await communicate.save("#{output.gsub('\\', '/')}")
          asyncio.run(main())
        PY

        Open3.popen3("#{python} -c #{script.inspect}") do |_, _, stderr, wait|
          wait.value.success? ? output : nil
        end
      end

      # Generate base64 for web embedding
      def generate_base64(text, voice: :aria, style: :normal)
        file = generate(text, voice: voice, style: style)
        return nil unless file && File.exist?(file)

        require 'base64'
        data = Base64.strict_encode64(File.binread(file))
        File.delete(file) rescue nil
        "data:audio/mp3;base64,#{data}"
      end

      # Speak immediately (blocking)
      def speak(text, voice: :aria, style: :normal)
        file = generate(text, voice: voice, style: style)
        return unless file && File.exist?(file)

        play_audio(file)
        File.delete(file) rescue nil
      end

      # List available voices
      def list_voices
        python = %w[py python3 python].find { |p| system("#{p} --version > /dev/null 2>&1") }
        output = `#{python} -c "import asyncio; import edge_tts; print(asyncio.run(edge_tts.list_voices()))" 2>/dev/null`
        output.scan(/'ShortName': '([^']+)'/).flatten
      rescue
        VOICES.values
      end

      private

      def play_audio(file)
        case RUBY_PLATFORM
        when /openbsd/
          system("mpv --no-video --really-quiet #{file} 2>/dev/null") ||
            system("ffplay -nodisp -autoexit -loglevel quiet #{file} 2>/dev/null")
        when /darwin/
          system("afplay #{file}")
        when /linux/
          system("mpv --no-video --really-quiet #{file} 2>/dev/null") ||
            system("ffplay -nodisp -autoexit -loglevel quiet #{file} 2>/dev/null")
        when /mingw|mswin|cygwin/
          system("powershell -c \"(New-Object Media.SoundPlayer '#{file}').PlaySync()\"")
        end
      end
    end
  end
end
