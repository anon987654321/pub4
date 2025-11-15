#!/usr/bin/env ruby
require "fileutils"
require "net/http"
require "uri"
require "cgi"
require "json"

$LOAD_PATH.unshift(File.expand_path("mb-sound/lib", __dir__))
begin
  require "mb-sound"
  MB_SOUND_AVAILABLE = true
rescue LoadError
  MB_SOUND_AVAILABLE = false
end

def find_sox
  ["sox.exe", "sox", "/usr/bin/sox.exe"].each do |path|
    return path if system("#{path} --version >/dev/null 2>&1")
  end
  nil
end

SOX_PATH = find_sox
abort "SoX not found" unless SOX_PATH

require_relative "__shared/@constants"
require_relative "__shared/@generators"
require_relative "__shared/@mastering"

PROGRESSIONS = Progression.load_all(File.join(__dir__, "__shared", "progressions.json"))

class DillaEngine
  include DillaConstants
  include SoxHelpers

  def initialize
    [@cache_dir = File.join(File.dirname(__dir__), ".cache"),
     CHECKPOINT_DIR, OUTPUT_DIR].each { |d| FileUtils.mkdir_p(d) }
    cleanup_old_checkpoints
    @pad_gen = PadGenerator.new
    @drums = DrumGenerator.new
    @mixer = Mixer.new
    @master = MasteringChain.new
  end

  def cleanup_old_checkpoints
    files = Dir.glob("#{CHECKPOINT_DIR}/*.wav")
    files.each { |f| File.delete(f) rescue nil } if files.size > 10
  end

  def generate_one_track
    prog_name = PROGRESSIONS.keys.sample
    prog = PROGRESSIONS[prog_name]
    puts "\n🎵 #{prog.name} (#{prog.tempo} BPM, swing: #{(prog.swing * 100).round}%)"

    drums = @drums.generate_drums(prog.tempo, prog.swing, 8)
    return nil unless drums

    pad_files = []
    4.times do |i|
      chord = prog.chords[i % prog.chords.length]
      pad = @pad_gen.generate_dreamy_pad(chord, prog.beat_duration * 8)
      pad_files << pad if pad
    end
    
    return nil if pad_files.empty?
    
    puts "  🎹 Combining #{pad_files.size} pad files..."
    combined_pads = tempfile("combined_pads")
    quoted_pads = pad_files.map { |p| "\"#{p}\"" }.join(" ")
    system("#{SOX_PATH} #{quoted_pads} \"#{combined_pads}\" 2>/dev/null")
    
    return nil unless valid?(combined_pads)
    cleanup_files(pad_files)

    puts "  🎸 Generating bass..."
    bass = generate_walking_bass(prog.bassline, prog.beat_duration * 32)
    return nil unless bass

    silence = generate_silence(prog.beat_duration * 32)
    mixed = @mixer.mix_tracks(drums, combined_pads, bass, silence)
    cleanup_files(silence)
    return nil unless mixed && valid?(mixed)

    output = @master.master_track(mixed)
    cleanup_files(drums, combined_pads, bass, mixed)
    
    if output && valid?(output)
      timestamp = Time.now.strftime("%Y%m%d_%H%M%S")
      filename = "#{prog.name.gsub(/[^a-zA-Z0-9]/, '_')}_#{timestamp}.wav"
      saved_file = File.join(Dir.pwd, filename)
      FileUtils.cp(output, saved_file)
      puts "💾 Saved: #{filename}"
      File.delete(output) rescue nil
      saved_file
    else
      nil
    end
  end

  private

  def generate_walking_bass(bassline, duration)
    out = "#{CHECKPOINT_DIR}/bass_#{Time.now.to_i}.wav"
    notes = {"C" => 130.81, "D" => 146.83, "E" => 164.81, "F" => 174.61,
             "G" => 196.00, "A" => 220.00, "B" => 246.94,
             "C#" => 138.59, "D#" => 155.56, "F#" => 184.99, "G#" => 207.65, "A#" => 233.08,
             "Db" => 138.59, "Eb" => 155.56, "Gb" => 184.99, "Ab" => 207.65, "Bb" => 233.08}

    note_dur = duration / bassline.length.to_f
    bass_notes = []
    
    bassline.each_with_index do |note, i|
      freq = notes[note] || 130.81
      note_file = tempfile("bass_note_#{i}")
      if system("#{SOX_PATH} -n \"#{note_file}\" synth #{note_dur} sine #{freq} sine #{freq * 2} sine #{freq * 0.5} fade h 0.01 #{note_dur} 0.08 overdrive 8 gain -4 2>/dev/null")
        bass_notes << note_file if valid?(note_file)
      end
    end
    
    return nil if bass_notes.empty?
    
    quoted_notes = bass_notes.map { |n| "\"#{n}\"" }.join(" ")
    system("#{SOX_PATH} #{quoted_notes} \"#{out}\" 2>/dev/null")
    cleanup_files(bass_notes)
    valid?(out) ? out : nil
  end

  def tempfile(prefix)
    "#{CHECKPOINT_DIR}/#{prefix}_#{Time.now.to_i}_#{rand(10000)}.wav"
  end

  def cleanup_files(*files)
    files.flatten.compact.each { |f| File.delete(f) rescue nil }
  end

  def generate_silence(duration)
    out = "#{CHECKPOINT_DIR}/silence_#{Time.now.to_i}.wav"
    system("#{SOX_PATH} -n \"#{out}\" synth #{duration} sine 0 vol 0 2>/dev/null")
    out
  end
end

if __FILE__ == $PROGRAM_NAME
  engine = DillaEngine.new
  result = engine.generate_one_track
  exit(result ? 0 : 1)
end
