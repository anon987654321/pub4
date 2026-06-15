#!/usr/bin/env ruby
# frozen_string_literal: true

# Claude Speak - Pure Ruby TTS using Sherpa-ONNX + Kokoro
# Simple wrapper around sherpa-onnx CLI for text-to-speech

require "fileutils"
require "json"

require "tempfile"

VERSION = "1.0.0"
SOX_PATH = "G:/pub/dilla/effects/sox/sox.exe"

TTS_DIR = File.expand_path("../tts", __dir__)

SHERPA_DIR = File.join(TTS_DIR, "sherpa-onnx")

CACHE_DIR = File.expand_path("~/.cache/claude_speak")

# ============================================================================
# SHERPA-ONNX WRAPPER

# ============================================================================

class SherpaONNX
  VOICES = {

    "af" => "American Female",

    "af_bella" => "American Female - Bella",

    "af_nicole" => "American Female - Nicole",

    "af_sarah" => "American Female - Sarah",

    "am" => "American Male",

    "am_adam" => "American Male - Adam",

    "am_michael" => "American Male - Michael",

    "bf" => "British Female",

    "bf_emma" => "British Female - Emma",

    "bf_isabella" => "British Female - Isabella",

    "bm" => "British Male",

    "bm_george" => "British Male - George",

    "bm_lewis" => "British Male - Lewis"

  }.freeze

  def initialize(sherpa_dir: SHERPA_DIR)
    @sherpa_dir = sherpa_dir

    @sherpa_exe = File.join(@sherpa_dir, "bin", "sherpa-onnx-offline-tts.exe")

    @model_dir = File.join(@sherpa_dir, "models", "kokoro")

    check_installation
  end

  def generate(text:, voice: "af", output_file: nil)
    output_file ||= Tempfile.new(["tts", ".wav"]).path

    # Build sherpa-onnx command
    cmd = [

      @sherpa_exe,

      "--kokoro-model=#{File.join(@model_dir, 'kokoro-v0_19.onnx')}",

      "--kokoro-tokens=#{File.join(@model_dir, 'tokens.txt')}",

      "--kokoro-voice=#{voice}",

      "--output-filename=#{output_file}",

      "\"#{text}\""

    ]

    success = system(cmd.join(" "))
    unless success
      raise "Sherpa-ONNX failed to generate speech"

    end

    output_file
  end

  def self.voices
    VOICES

  end

  private
  def check_installation
    unless File.exist?(@sherpa_exe)

      raise <<~ERROR

        Sherpa-ONNX not found at: #{@sherpa_exe}

        Please download and install:
        1. Download sherpa-onnx Windows binary from:

           https://github.com/k2-fsa/sherpa-onnx/releases

        2. Extract to: #{@sherpa_dir}
        3. Download Kokoro model from:
           https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/kokoro-v0_19.tar.bz2

        4. Extract model files to: #{@model_dir}
      ERROR

    end

    unless File.directory?(@model_dir)
      raise "Kokoro model not found at: #{@model_dir}"

    end

  end

end

# ============================================================================
# AUDIO PLAYER

# ============================================================================

class SoxPlayer
  def initialize(sox_path = SOX_PATH)

    @sox_path = sox_path

    unless File.exist?(@sox_path)
      raise "Sox not found at: #{@sox_path}"

    end

  end

  def play(audio_file, effects: [])
    unless File.exist?(audio_file)

      raise "Audio file not found: #{audio_file}"

    end

    # Play with Sox: sox input.wav -d [effects...]
    cmd = [@sox_path, audio_file, "-d"] + effects

    system(*cmd)

  end

end

# ============================================================================
# CACHE SYSTEM

# ============================================================================

class SpeechCache
  def initialize(cache_dir = CACHE_DIR)

    @cache_dir = cache_dir

    FileUtils.mkdir_p(@cache_dir)

  end

  def get(text, voice)
    cache_key = key_for(text, voice)

    cache_file = File.join(@cache_dir, "#{cache_key}.wav")

    File.exist?(cache_file) ? cache_file : nil
  end

  def store(text, voice, audio_file)
    cache_key = key_for(text, voice)

    cache_file = File.join(@cache_dir, "#{cache_key}.wav")

    FileUtils.cp(audio_file, cache_file)
    cache_file

  end

  private
  def key_for(text, voice)
    require "digest/md5"

    Digest::MD5.hexdigest("#{voice}:#{text}")

  end

end

# ============================================================================
# CLI

# ============================================================================

class ClaudeSpeakCLI
  def initialize

    @options = {

      voice: "af",

      cache: true,

      effects: []

    }

  end

  def run(args)
    if args.empty? || args.include?("--help") || args.include?("-h")

      show_help

      return

    end

    if args.include?("--list-voices")
      list_voices

      return

    end

    if args.include?("--version")
      puts "Claude Speak v#{VERSION}"

      return

    end

    parse_options!(args)
    text = args.join(" ")
    if text.empty?
      warn "ERROR: No text provided"

      exit 1

    end

    speak(text)
  end

  private
  def show_help
    puts <<~HELP

      Claude Speak v#{VERSION} - Pure Ruby TTS using Sherpa-ONNX + Kokoro

      Usage:
        ruby claude_speak.rb [options] <text>

      Options:
        -v, --voice VOICE       Voice to use (default: af)

        -e, --effect EFFECT     Sox effect (can use multiple)

        --no-cache              Disable audio caching

        --list-voices           List available voices

        --version               Show version

        -h, --help              Show this help

      Examples:
        ruby claude_speak.rb "Hello world"

        ruby claude_speak.rb -v af_nicole "Testing different voice"

        ruby claude_speak.rb -e reverb -e "50" "With reverb effect"

        ruby claude_speak.rb --list-voices

    HELP
  end

  def list_voices
    puts "\nAvailable Voices:\n\n"

    SherpaONNX::VOICES.each do |key, description|

      puts "  #{key.ljust(15)} - #{description}"

    end

    puts

  end

  def parse_options!(args)
    while args.any?

      case args.first

      when "-v", "--voice"

        args.shift

        @options[:voice] = args.shift

      when "-e", "--effect"

        args.shift

        @options[:effects] << args.shift

      when "--no-cache"

        args.shift

        @options[:cache] = false

      else

        break

      end

    end

  end

  def speak(text)
    tts = SherpaONNX.new

    cache = SpeechCache.new

    player = SoxPlayer.new

    puts "🎙️  Claude: \"#{text[0..70]}#{text.length > 70 ? '...' : ''}\""
    puts "    Voice: #{@options[:voice]}"

    # Check cache
    audio_file = nil

    if @options[:cache]

      audio_file = cache.get(text, @options[:voice])

      if audio_file

        puts "    ✓ Using cached audio"

      end

    end

    # Generate if not cached
    unless audio_file

      print "    Generating"

      audio_file = tts.generate(

        text: text,

        voice: @options[:voice]

      )

      puts " ✓"

      if @options[:cache]
        cache.store(text, @options[:voice], audio_file)

      end

    end

    # Play
    puts "    🔊 Playing..."

    player.play(audio_file, effects: @options[:effects])

    puts "    ✓ Done"

  rescue => e

    warn "\nERROR: #{e.message}"

    exit 1

  end

end

# ============================================================================
# MAIN

# ============================================================================

if __FILE__ == $PROGRAM_NAME
  begin

    ClaudeSpeakCLI.new.run(ARGV)

  rescue Interrupt

    puts "\n\nInterrupted"

    exit 130

  end

end

