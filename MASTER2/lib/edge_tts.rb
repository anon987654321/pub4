# frozen_string_literal: true

require 'net/http'
require 'json'
require 'open3'

module MASTER
  # EdgeTTS - Free Microsoft TTS via edge-tts CLI
  # No API key required, 400+ voices
  module EdgeTTS
    extend self

    VOICES = {
      aria:     'en-US-AriaNeural',
      guy:      'en-US-GuyNeural',
      jenny:    'en-US-JennyNeural',
      davis:    'en-US-DavisNeural',
      sara:     'en-US-SaraNeural',
      tony:     'en-US-TonyNeural',
      nancy:    'en-US-NancyNeural',
      amber:    'en-US-AmberNeural',
      ana:      'en-US-AnaNeural',
      brandon:  'en-US-BrandonNeural',
      # British
      sonia:    'en-GB-SoniaNeural',
      ryan:     'en-GB-RyanNeural',
      # Australian  
      natasha:  'en-AU-NatashaNeural',
      william:  'en-AU-WilliamNeural'
    }.freeze

    DEFAULT_VOICE = :aria

    class << self
      def installed?
        system('which edge-tts > /dev/null 2>&1') || 
        system('where edge-tts > nul 2>&1')
      end

      def install_hint
        "pip install edge-tts"
      end

      def speak(text, voice: DEFAULT_VOICE, output: nil)
        return Result.err("edge-tts not installed. Run: #{install_hint}") unless installed?

        voice_name = VOICES[voice.to_sym] || VOICES[DEFAULT_VOICE]
        output ||= File.join(Paths.tmp, "tts_#{Time.now.to_i}.mp3")

        cmd = ['edge-tts', '--voice', voice_name, '--text', text, '--write-media', output]

        stdout, stderr, status = Open3.capture3(*cmd)

        if status.success? && File.exist?(output)
          Result.ok(output)
        else
          Result.err("TTS failed: #{stderr}")
        end
      end

      def speak_and_play(text, voice: DEFAULT_VOICE)
        result = speak(text, voice: voice)
        return result if result.err?

        play(result.value)
        Result.ok(result.value)
      end

      def play(file)
        if Shell.which('afplay')
          system('afplay', file)
        elsif Shell.which('mpv')
          system('mpv', '--no-video', file)
        elsif Shell.which('ffplay')
          system('ffplay', '-nodisp', '-autoexit', file)
        else
          puts "No audio player found. File saved at: #{file}"
        end
      end

      def list_voices
        return [] unless installed?
        output = `edge-tts --list-voices 2>/dev/null`
        output.lines.map(&:strip).reject(&:empty?)
      rescue
        []
      end

      def generate_base64(text, voice: DEFAULT_VOICE)
        result = speak(text, voice: voice)
        return nil if result.err?

        require 'base64'
        data = Base64.strict_encode64(File.binread(result.value))
        File.delete(result.value) rescue nil
        "data:audio/mp3;base64,#{data}"
      end
    end
  end
end
