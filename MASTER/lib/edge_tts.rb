# frozen_string_literal: true

require 'open3'
require 'fileutils'
require 'securerandom'

module MASTER
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
