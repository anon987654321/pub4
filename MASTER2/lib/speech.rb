# frozen_string_literal: true

require "fileutils"
require "securerandom"

module MASTER
  # Speech - Unified TTS interface with multiple engines
  # Priority: Piper (local) → Edge (free cloud) → Replicate (paid cloud)
  # Stream mode uses FFmpeg for real-time effects
  module Speech
    extend self

    # Engine selection priority
    ENGINES = %i[piper edge replicate].freeze

    # FFmpeg effect presets for streaming
    STREAM_EFFECTS = {
      dark: "asetrate=44100*0.8,atempo=1.25,bass=g=10",
      demon: "asetrate=44100*0.7,atempo=1.4,bass=g=15,acompressor=threshold=0.08:ratio=12",
      robot: "asetrate=44100*0.9,atempo=1.1,flanger,tremolo=f=10:d=0.5",
      radio: "highpass=f=300,lowpass=f=3000,acompressor=threshold=0.1:ratio=8",
      underwater: "asetrate=44100*0.6,atempo=1.6,lowpass=f=800,chorus=0.5:0.9:50:0.4:0.25:2",
      ghost: "asetrate=44100*0.75,atempo=1.33,areverse,aecho=0.8:0.88:60:0.4,areverse",
    }.freeze

    # Voice styles (rate/pitch adjustments for Edge)
    STYLES = {
      normal: { rate: "+0%", pitch: "+0Hz" }.freeze,
      fast: { rate: "+25%", pitch: "+0Hz" }.freeze,
      slow: { rate: "-20%", pitch: "+0Hz" }.freeze,
      high: { rate: "+0%", pitch: "+50Hz" }.freeze,
      low: { rate: "+0%", pitch: "-50Hz" }.freeze,
      excited: { rate: "+15%", pitch: "+30Hz" }.freeze,
      calm: { rate: "-10%", pitch: "-20Hz" }.freeze,
      whisper: { rate: "-15%", pitch: "-30Hz" }.freeze,
      urgent: { rate: "+30%", pitch: "+20Hz" }.freeze,
    }.freeze

    # Piper voice presets (length_scale/noise_scale)
    PIPER_PRESETS = {
      normal: { length_scale: 1.0, noise_scale: 0.667 }.freeze,
      chipmunk: { length_scale: 0.6, noise_scale: 0.667 }.freeze,
      zombie: { length_scale: 2.5, noise_scale: 0.4 }.freeze,
      robot: { length_scale: 1.0, noise_scale: 0.1 }.freeze,
      manic: { length_scale: 0.8, noise_scale: 0.9 }.freeze,
      calm: { length_scale: 1.2, noise_scale: 0.3 }.freeze,
      urgent: { length_scale: 0.7, noise_scale: 0.5 }.freeze,
      demon: { length_scale: 3.0, noise_scale: 0.3 }.freeze,
      caffeinated: { length_scale: 0.5, noise_scale: 0.7 }.freeze,
    }.freeze

    # Edge TTS voices
    EDGE_VOICES = {
      aria: "en-US-AriaNeural",
      guy: "en-US-GuyNeural",
      jenny: "en-US-JennyNeural",
      davis: "en-US-DavisNeural",
      sonia: "en-GB-SoniaNeural",
      ryan: "en-GB-RyanNeural",
      finn: "nb-NO-FinnNeural",
      pernille: "nb-NO-PernilleNeural",
    }.freeze

    # Speak text using best available engine
    def speak(text, engine: nil, voice: nil, style: :normal, play: true)
      return Result.err("Empty text") if text.nil? || text.strip.empty?

      engine ||= best_engine
      return Result.err("No TTS engine available") unless engine

      case engine
      when :piper then speak_piper(text, voice: voice, preset: style, play: play)
      when :edge then speak_edge(text, voice: voice, style: style, play: play)
      when :replicate then speak_replicate(text, play: play)
      else Result.err("Unknown engine: #{engine}")
      end
    end

    # Stream with real-time FFmpeg effects (requires edge-tts + ffmpeg)
    def stream(text, effect: :dark, voice: :guy, rate: "-25%", pitch: "-25Hz")
      python = find_python
      return Result.err("Python not found") unless python
      return Result.err("edge-tts not installed") unless edge_installed?

      voice_id = EDGE_VOICES[voice.to_sym] || EDGE_VOICES[:guy]
      fx_filter = STREAM_EFFECTS[effect.to_sym] || STREAM_EFFECTS[:dark]

      ffmpeg = ENV["FFMPEG_PATH"] || "ffmpeg"
      ffplay = ENV["FFPLAY_PATH"] || "ffplay"

      tts_cmd = [python, "-m", "edge_tts",
                 "--text", text,
                 "--voice", voice_id,
                 "--rate=#{rate}",
                 "--pitch=#{pitch}",
                 "--write-media", "-"]

      null = RUBY_PLATFORM =~ /mingw|mswin|cygwin/ ? "NUL" : "/dev/null"

      tts = IO.popen(tts_cmd, "rb", err: null)
      fx = IO.popen([ffmpeg, "-i", "pipe:0", "-af", fx_filter, "-f", "wav", "pipe:1"], "r+b", err: null)
      play = IO.popen([ffplay, "-nodisp", "-autoexit", "-i", "pipe:0"], "wb", err: null)

      Thread.new { IO.copy_stream(tts, fx); fx.close_write }
      IO.copy_stream(fx, play)

      [tts, fx, play].each(&:close)
      Result.ok(text: text, effect: effect)
    rescue StandardError => e
      Result.err("Stream failed: #{e.message}")
    end

    # Demon mode (maximum darkness effect)
    def demon(text)
      stream(text, effect: :demon, rate: "-35%", pitch: "-35Hz")
    end

    # Continuous chatter mode (for Windows background talking)
    def chatter(topic: :master, effect: :calm, delay: 2.0)
      topics = {
        master: [
          "Consider adding a visual diff preview before applying changes.",
          "What if MASTER could learn from rejected suggestions?",
          "The axiom enforcement could have graduated severity levels.",
          "A cost projection before expensive operations would build trust.",
          "Self-test on boot ensures integrity after updates.",
        ],
        code: [
          "Extract that repeated pattern into a shared helper.",
          "This function does two things. Consider splitting it.",
          "Add a timeout to that external call.",
          "The magic number should be a named constant.",
        ],
        philosophy: [
          "Simplicity is the ultimate sophistication.",
          "Make it work, make it right, make it fast.",
          "The best code is no code at all.",
        ],
      }

      suggestions = topics[topic.to_sym] || topics[:master]
      loop do
        stream(suggestions.sample, effect: effect)
        sleep delay
      end
    end

    # Engine availability checks
    def best_engine
      return :piper if piper_installed?
      return :edge if edge_installed?
      return :replicate if ENV["REPLICATE_API_TOKEN"]
      nil
    end

    def piper_installed?
      system("piper --version > /dev/null 2>&1") ||
        system("py -m piper --version > nul 2>&1")
    end

    def edge_installed?
      python = find_python
      return false unless python
      system("#{python} -c \"import edge_tts\" 2>/dev/null")
    end

    def install_edge!
      python = find_python
      system("#{python} -m pip install edge-tts --quiet") if python
    end

    def available_engines
      ENGINES.select do |e|
        case e
        when :piper then piper_installed?
        when :edge then edge_installed?
        when :replicate then ENV["REPLICATE_API_TOKEN"]
        end
      end
    end

    def engine_status
      engines = available_engines
      return "off" if engines.empty?
      engines.map(&:to_s).join("/")
    end

    private

    # Piper TTS (local)
    def speak_piper(text, voice: nil, preset: :normal, play: true)
      voice ||= "en_US-lessac-medium"
      params = PIPER_PRESETS[preset.to_sym] || PIPER_PRESETS[:normal]

      voices_dir = File.join(Paths.var, "piper_voices")
      FileUtils.mkdir_p(voices_dir)
      model = File.join(voices_dir, "#{voice}.onnx")

      output = File.join(Dir.tmpdir, "piper_#{SecureRandom.hex(4)}.wav")
      escaped = text.gsub('"', '\\"').gsub("`", "\\`")

      cmd = if RUBY_PLATFORM =~ /mingw|mswin|cygwin/
              "echo #{escaped} | py -m piper --model #{model} --output #{output} --length_scale #{params[:length_scale]} --noise_scale #{params[:noise_scale]}"
            else
              "echo \"#{escaped}\" | piper --model #{model} --output_file #{output} --length_scale #{params[:length_scale]} --noise_scale #{params[:noise_scale]} 2>/dev/null"
            end

      success = system(cmd)
      return Result.err("Piper generation failed") unless success && File.exist?(output)

      play_audio(output) if play
      FileUtils.rm_f(output) if play

      Result.ok(engine: :piper, voice: voice, preset: preset)
    end

    # Edge TTS (free cloud)
    def speak_edge(text, voice: nil, style: :normal, play: true)
      python = find_python
      return Result.err("Python not found") unless python

      voice_id = EDGE_VOICES[voice&.to_sym] || EDGE_VOICES[:aria]
      params = STYLES[style.to_sym] || STYLES[:normal]

      output_dir = Paths.edge_tts_output
      FileUtils.mkdir_p(output_dir)
      output = File.join(output_dir, "edge_#{SecureRandom.hex(4)}.mp3")

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

      success = system("#{python} -c #{script.inspect} 2>/dev/null")
      return Result.err("Edge TTS generation failed") unless success && File.exist?(output)

      play_audio(output) if play
      FileUtils.rm_f(output) if play

      Result.ok(engine: :edge, voice: voice_id, style: style)
    end

    # Replicate TTS (paid cloud)
    def speak_replicate(text, play: true)
      require "net/http"
      require "json"

      token = ENV["REPLICATE_API_TOKEN"]
      return Result.err("No REPLICATE_API_TOKEN") unless token

      uri = URI("https://api.replicate.com/v1/models/minimax/speech-02-turbo/predictions")
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true

      request = Net::HTTP::Post.new(uri)
      request["Authorization"] = "Bearer #{token}"
      request["Content-Type"] = "application/json"
      request["Prefer"] = "wait"
      request.body = { input: { text: text, voice_id: "Casual_Guy" } }.to_json

      response = http.request(request)
      data = JSON.parse(response.body)

      audio_url = data["output"]
      return Result.err("No audio URL returned") unless audio_url

      if play
        temp = File.join(Dir.tmpdir, "replicate_#{SecureRandom.hex(4)}.wav")
        download_and_play(audio_url, temp)
      end

      Result.ok(engine: :replicate, url: audio_url)
    rescue StandardError => e
      Result.err("Replicate error: #{e.message}")
    end

    def download_and_play(url, temp_file)
      require "net/http"
      uri = URI(url)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == "https"
      response = http.get(uri.request_uri)
      File.binwrite(temp_file, response.body)
      play_audio(temp_file)
      FileUtils.rm_f(temp_file)
    end

    def play_audio(file)
      return unless file && File.exist?(file)

      case RUBY_PLATFORM
      when /openbsd/
        system("aucat -i #{file} 2>/dev/null") || system("mpv --no-video #{file} 2>/dev/null")
      when /darwin/
        system("afplay #{file}")
      when /linux/
        system("mpv --no-video --really-quiet #{file} 2>/dev/null") ||
          system("aplay -q #{file} 2>/dev/null") ||
          system("paplay #{file} 2>/dev/null")
      when /mingw|mswin|cygwin/
        system("powershell -c \"(New-Object Media.SoundPlayer '#{file}').PlaySync()\"")
      end
    end

    def find_python
      %w[py python3 python].find { |p| system("#{p} --version > /dev/null 2>&1") } || "python"
    end
  end
end
