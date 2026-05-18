# frozen_string_literal: true

require "open3"

module Master
  module Voice
  class FfmpegLofi
    Error = Class.new(StandardError)

    PRESETS = {
      clean: [],
      tts_vintage: [
        "highpass=f=80",
        "acrusher=bits=12:samples=1:mix=0.7:mode=log:aa=1",
        "lowpass=f=6000",
        "tremolo=f=0.3:d=0.05",
        "volume=0.9"
      ],
      intelligible_crush: [
        "highpass=f=80",
        "acrusher=bits=12:samples=1:mix=0.45:mode=log:aa=1",
        "lowpass=f=8000",
        "volume=0.95"
      ],
      phone: [
        "highpass=f=300",
        "lowpass=f=3400",
        "acompressor=threshold=-18dB:ratio=3:attack=5:release=50"
      ]
    }.freeze

    attr_reader :ffmpeg

    def initialize(ffmpeg: nil)
      @ffmpeg = ffmpeg || self.class.find_ffmpeg
    end

    def self.find_ffmpeg
      ENV["FFMPEG"].to_s.then { |path| return path if !path.empty? && File.executable?(path) }
      %w[/usr/local/bin/ffmpeg /usr/bin/ffmpeg ffmpeg].find { |path| executable_command?(path) }
    end

    def self.executable_command?(path)
      return File.executable?(path) if path.include?(File::SEPARATOR)

      system("command", "-v", path, out: File::NULL, err: File::NULL)
    end

    def self.brief
      "FFmpeg lofi TTS: default clean; opt-in effects. Preferred chain: highpass 80, acrusher 12-bit log anti-aliased, lowpass 5-8kHz, subtle tremolo."
    end

    def command(input, output, preset: :tts_vintage)
      filters = PRESETS.fetch(preset.to_sym) { raise Error, "unknown ffmpeg lofi preset: #{preset}" }
      args = [ffmpeg!, "-y", "-i", input.to_s]
      args.concat(["-af", filters.join(",")]) unless filters.empty?
      args << output.to_s
      args
    end

    def process(input, output, preset: :tts_vintage)
      run(command(input, output, preset: preset))
      output
    end

    def available?
      !!ffmpeg
    end

    private

    def ffmpeg!
      raise Error, "ffmpeg not found; set FFMPEG=/path/to/ffmpeg" unless ffmpeg

      ffmpeg
    end

    def run(argv)
      _out, err, status = Open3.capture3(*argv)
      raise Error, err.strip.empty? ? "ffmpeg failed" : err.strip unless status.success?
    end
  end
  end
end
