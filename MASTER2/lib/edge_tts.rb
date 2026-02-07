# frozen_string_literal: true

require "open3"
require "fileutils"
require "securerandom"

module MASTER
  # EdgeTTS: Free unlimited Microsoft neural voices via edge-tts Python package
  # Zero cost, 400+ voices, 150ms latency, no API key needed
  module EdgeTTS
    extend self

    OUTPUT_DIR = File.join(Paths.var, "edge_tts")

    # Popular voices - neural quality, many languages
    VOICES = {
      # English US
      aria: "en-US-AriaNeural",
      guy: "en-US-GuyNeural",
      jenny: "en-US-JennyNeural",
      davis: "en-US-DavisNeural",
      sara: "en-US-SaraNeural",
      tony: "en-US-TonyNeural",
      nancy: "en-US-NancyNeural",
      # English UK
      sonia: "en-GB-SoniaNeural",
      ryan: "en-GB-RyanNeural",
      # Norwegian
      finn: "nb-NO-FinnNeural",
      pernille: "nb-NO-PernilleNeural",
      iselin: "nb-NO-IselinNeural",
      # Other languages
      seraphina: "de-DE-SeraphinaMultilingualNeural",
      vivienne: "fr-FR-VivienneMultilingualNeural",
      florian: "de-DE-FlorianMultilingualNeural",
    }.freeze

    # Pitch/rate adjustments
    STYLES = {
      normal: { rate: "+0%", pitch: "+0Hz" },
      fast: { rate: "+25%", pitch: "+0Hz" },
      slow: { rate: "-20%", pitch: "+0Hz" },
      high: { rate: "+0%", pitch: "+50Hz" },
      low: { rate: "+0%", pitch: "-50Hz" },
      excited: { rate: "+15%", pitch: "+30Hz" },
      calm: { rate: "-10%", pitch: "-20Hz" },
      whisper: { rate: "-15%", pitch: "-30Hz" },
      urgent: { rate: "+30%", pitch: "+20Hz" },
    }.freeze

    DEFAULT_VOICE = :aria

    class << self
      def installed?
        system('python -c "import edge_tts" 2>/dev/null') ||
          system('python3 -c "import edge_tts" 2>/dev/null') ||
          system('py -c "import edge_tts" 2>/dev/null')
      end

      def install!
        python = find_python
        system("#{python} -m pip install edge-tts --quiet")
      end

      def install_hint
        "pip install edge-tts"
      end

      def speak(text, voice: DEFAULT_VOICE, style: :normal, output: nil)
        return Result.err("edge-tts not installed. Run: #{install_hint}") unless installed?
        return Result.err("Empty text") if text.nil? || text.strip.empty?

        FileUtils.mkdir_p(OUTPUT_DIR)
        output ||= File.join(OUTPUT_DIR, "edge_#{SecureRandom.hex(4)}.mp3")

        voice_id = VOICES[voice.to_sym] || VOICES[DEFAULT_VOICE]
        params = STYLES[style.to_sym] || STYLES[:normal]

        python = find_python

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
          if wait.value.success? && File.exist?(output)
            Result.ok(output)
          else
            Result.err("TTS failed: #{stderr.read}")
          end
        end
      end

      def speak_and_play(text, voice: DEFAULT_VOICE, style: :normal)
        result = speak(text, voice: voice, style: style)
        return result if result.err?

        play(result.value)
        File.delete(result.value) rescue nil
        Result.ok(text)
      end

      def play(file)
        return unless file && File.exist?(file)

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

      def generate_base64(text, voice: DEFAULT_VOICE, style: :normal)
        result = speak(text, voice: voice, style: style)
        return nil if result.err?

        require "base64"
        data = Base64.strict_encode64(File.binread(result.value))
        File.delete(result.value) rescue nil
        "data:audio/mp3;base64,#{data}"
      end

      def list_voices
        return VOICES.values unless installed?

        python = find_python
        output = `#{python} -c "import asyncio; import edge_tts; print(asyncio.run(edge_tts.list_voices()))" 2>/dev/null`
        output.scan(/'ShortName': '([^']+)'/).flatten
      rescue StandardError
        VOICES.values
      end

      private

      def find_python
        %w[py python3 python].find { |p| system("#{p} --version > /dev/null 2>&1") } || "python"
      end
    end
  end
end
