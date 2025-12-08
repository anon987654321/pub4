#!/usr/bin/env ruby
# frozen_string_literal: true

# Dilla v74.0.0 - J Dilla Beat Generator (Consolidated)
# Produces complete tracks using J Dilla's chord progressions and microtiming
# Dependencies: SoX (pkg_add sox on OpenBSD)

require "fileutils"
require "net/http"
require "uri"
require "cgi"
require "json"

def find_sox
  ["sox.exe", "sox", "/usr/bin/sox", "/usr/local/bin/sox"].each do |path|
    return path if system("#{path} --version >/dev/null 2>&1")
  end
  nil
end

SOX_PATH = find_sox
abort "SoX not found - install with: pkg_add sox" unless SOX_PATH
puts "[INIT] SoX: #{SOX_PATH}"

module DillaConstants
  CACHE_DIR = File.join(File.dirname(__dir__), ".cache")
  CHECKPOINT_DIR = File.join(CACHE_DIR, "checkpoints")
  TTS_CACHE_DIR = File.join(CACHE_DIR, "tts_cache")
  OUTPUT_DIR = File.join(CACHE_DIR, "output")
  MIN_FILE_SIZE = 500
  RANDOM_RANGE = 10_000
  DEBUG = ENV["DEBUG"] == "1"
end

module SoxHelpers
  include DillaConstants

  def sox_cmd(args)
    command = "#{SOX_PATH} #{args}"
    puts "[DEBUG] SoX: #{command}" if DEBUG
    command
  end

  def tempfile(prefix)
    "#{CHECKPOINT_DIR}/#{prefix}_#{Time.now.to_i}_#{rand(RANDOM_RANGE)}.wav"
  end

  def valid?(file)
    file && File.exist?(file) && File.size(file) > MIN_FILE_SIZE
  end

  def cleanup_files(*files)
    files.flatten.compact.each { |f| File.delete(f) rescue nil }
  end
end

NOTES = {
  "C" => 261.63, "Db" => 277.18, "D" => 293.66, "Eb" => 311.13,
  "E" => 329.63, "F" => 349.23, "Gb" => 369.99, "G" => 392.00,
  "Ab" => 415.30, "A" => 440.00, "Bb" => 466.16, "B" => 493.88,
  "C#" => 277.18, "D#" => 311.13, "F#" => 369.99, "G#" => 415.30, "A#" => 466.16
}.freeze

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

PROGRESSIONS = Progression.load_all(File.join(__dir__, "progressions.json"))
