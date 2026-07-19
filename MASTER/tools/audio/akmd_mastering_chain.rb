#!/usr/bin/env ruby
# frozen_string_literal: true
# frozen_string_literal: true

require "fileutils"
require "open3"
require "optparse"

module Pub4Audio
  class AkmdMasteringChain
    FILTERS = [
      "highpass=f=60",
      "lowpass=f=11500",
      "equalizer=f=80:t=q:w=1.5:g=3",
      "equalizer=f=200:t=q:w=1:g=2",
      "equalizer=f=8000:t=q:w=2:g=-3",
      "acompressor=threshold=-20dB:ratio=3:attack=10:release=80:makeup=4",
      "asoftclip=type=tanh",
      "volume=1.5",
      "alimiter=limit=0.92:attack=3:release=50",
    ].freeze

    DEFAULT_BITRATE = "128k"
    DEFAULT_RATE = "44100"

    def initialize(input:, output:, bitrate: DEFAULT_BITRATE, sample_rate: DEFAULT_RATE)
      @input = File.expand_path(input)
      @output = File.expand_path(output)
      @bitrate = bitrate
      @sample_rate = sample_rate
    end

    def call
      validate!
      FileUtils.mkdir_p(File.dirname(output))

      stdout, stderr, status = Open3.capture3(*command)
      return true if status.success?

      warn stderr unless stderr.empty?
      warn stdout unless stdout.empty?
      false
    end

    def command
      [
        ffmpeg,
        "-hide_banner",
        "-y",
        "-i", input,
        "-af", FILTERS.join(","),
        "-ar", sample_rate,
        "-ac", "2",
        "-codec:a", "libmp3lame",
        "-b:a", bitrate,
        output,
      ]
    end

    private

    attr_reader :input, :output, :bitrate, :sample_rate

    def validate!
      raise ArgumentError, "input missing: #{input}" unless File.file?(input)
      raise ArgumentError, "output must end in .mp3" unless output.end_with?(".mp3")
      raise ArgumentError, "invalid bitrate: #{bitrate}" unless bitrate.match?(/\A\d+k\z/)
      raise ArgumentError, "invalid sample rate: #{sample_rate}" unless sample_rate.match?(/\A\d+\z/)
    end

    def ffmpeg
      ENV.fetch("FFMPEG", "ffmpeg")
    end
  end
end

if $PROGRAM_NAME == __FILE__
  options = {
    bitrate: Pub4Audio::AkmdMasteringChain::DEFAULT_BITRATE,
    sample_rate: Pub4Audio::AkmdMasteringChain::DEFAULT_RATE,
  }

  parser = OptionParser.new do |opts|
    opts.banner = "Usage: ruby OPENBSD/audio/akmd_mastering_chain.rb INPUT OUTPUT.mp3 [options]"
    opts.on("--bitrate VALUE", "MP3 bitrate, default 128k") { |value| options[:bitrate] = value }
    opts.on("--sample-rate VALUE", "Sample rate, default 44100") { |value| options[:sample_rate] = value }
    opts.on("--print-command", "Print ffmpeg argv and exit") { options[:print_command] = true }
  end

  parser.parse!
  input, output = ARGV

  unless input && output
    warn parser
    exit 64
  end

  chain = Pub4Audio::AkmdMasteringChain.new(
    input: input,
    output: output,
    bitrate: options.fetch(:bitrate),
    sample_rate: options.fetch(:sample_rate)
  )

  if options[:print_command]
    puts chain.command.shelljoin
    exit 0
  end

  exit(chain.call ? 0 : 1)
end
