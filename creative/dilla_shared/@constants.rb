# frozen_string_literal: true

module DillaConstants
  CACHE_DIR = File.join(File.dirname(__dir__), ".cache")
  CHECKPOINT_DIR = File.join(CACHE_DIR, "checkpoints")
  TTS_CACHE_DIR = File.join(CACHE_DIR, "tts_cache")
  OUTPUT_DIR = File.join(CACHE_DIR, "output")
  STREAM_FILE = "#{CHECKPOINT_DIR}/live_stream.wav"
  AMBIENT_DRONE_FILE = "#{CHECKPOINT_DIR}/ambient_drone.wav"
  SOUNDFONT_PATH = "#{Dir.pwd}/Jnsgm2.sf2".freeze
  RHODES_PROG = 4
  MIN_FILE_SIZE = 500
  RANDOM_RANGE = 10_000
  DEFAULT_BARS = 64
  AMBIENT_DRONE_DURATION = 300
  MB_SOUND_CONFIG = { sample_rate: 44100, channels: 2 }.freeze
  DEBUG = ENV["DEBUG"] == "1"
  FLUIDSYNTH_AVAILABLE = system("fluidsynth --version >/dev/null 2>&1")
end

module SoxHelpers
  include DillaConstants

  def sox_cmd(args)
    command = "#{SOX_PATH} #{args}"
    puts "[DEBUG] SoX CMD: #{command}" if DEBUG
    command
  end

  def tempfile(prefix)
    filename = "#{CHECKPOINT_DIR}/#{prefix}_#{Time.now.to_i}_#{rand(RANDOM_RANGE)}.wav"
    puts "[DEBUG] Tempfile: #{filename}" if DEBUG
    filename
  end

  def valid?(file)
    return false unless file && File.exist?(file)
    file_size = File.size(file)
    result = file_size > MIN_FILE_SIZE

    if DEBUG
      puts "[DEBUG] valid?(#{File.basename(file)}) = #{result}"
      puts "[DEBUG]   size: #{file_size} bytes (min: #{MIN_FILE_SIZE})"
    end
    result
  end

  def cleanup_files(*files)
    files.flatten.compact.each { |f| File.delete(f) rescue nil }
  end
end

class Progression
  attr_reader :name, :tempo, :swing, :chords, :bassline, :arrangement

  def initialize(name:, tempo:, swing:, chords:, bassline:, arrangement:)
    @name = name
    @tempo = tempo
    @swing = swing
    @chords = chords.freeze
    @bassline = bassline.freeze
    @arrangement = arrangement.freeze
  end

  def beat_duration
    60.0 / tempo
  end

  def self.load_all(json_path)
    data = JSON.parse(File.read(json_path))
    data.transform_values do |prog|
      new(
        name: prog["name"],
        tempo: prog["tempo"],
        swing: prog["swing"],
        chords: prog["chords"],
        bassline: prog["bassline"],
        arrangement: prog["arrangement"].transform_keys(&:to_sym)
      )
    end.transform_keys(&:to_sym)
  end
end
