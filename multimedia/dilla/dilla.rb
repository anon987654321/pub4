#!/usr/bin/env ruby
# frozen_string_literal: true

# v73.0.0 - Dilla (modular architecture - master.json compliant)
require "fileutils"
require "net/http"
require "uri"
require "cgi"
require "json"

$LOAD_PATH.unshift(File.expand_path("mb-sound/lib", __dir__))
begin
  require "mb-sound"
  MB_SOUND_AVAILABLE = true
  puts "[INIT] ✅ mb-sound loaded"
rescue LoadError => e
  MB_SOUND_AVAILABLE = false
  puts "[INIT] ⚠️  mb-sound unavailable: #{e.message}"
end

def find_sox
  candidates = [
    "sox.exe",
    "sox",
    "/usr/bin/sox.exe",
    "/usr/bin/sox",
    "/c/cygwin64/bin/sox.exe",
    File.expand_path("../dilla/effects/sox/sox.exe", __dir__)
  ]
  candidates.each do |path|
    if system("#{path} --version >/dev/null 2>&1")
      puts "[INIT] ✅ SoX found: #{path}"
      return path
    end
  end
  nil
end

SOX_PATH = find_sox
abort "❌ SoX not found in PATH or common locations" unless SOX_PATH

require_relative "__shared/@constants"
require_relative "__shared/@generators"
require_relative "__shared/@mastering"
require_relative "__shared/@tts"

PROGRESSIONS = Progression.load_all(File.join(__dir__, "__shared", "progressions.json"))

class DillaEngine
  include DillaConstants

  def initialize
    FileUtils.mkdir_p(CHECKPOINT_DIR)
    FileUtils.mkdir_p(TTS_CACHE_DIR)
    FileUtils.mkdir_p(OUTPUT_DIR)
    cleanup_old_checkpoints
    @professor = CraneTTS.new
    @pad_gen = PadGenerator.new
    @drums = DrumGenerator.new
    @mixer = Mixer.new
    @master = MasteringChain.new
  end

  def cleanup_old_checkpoints
    files = Dir.glob("#{CHECKPOINT_DIR}/*.wav")
    if files.size > 10
      puts "[CLEANUP] Removing #{files.size} old checkpoint files..."
      files.each { |f| File.delete(f) rescue nil }
      puts "[CLEANUP] ✓ Checkpoints cleaned"
    end
  end

  def generate_track(progression_name)
    prog = PROGRESSIONS[progression_name]
    puts "\n🎵 #{prog.name} (#{prog.tempo} BPM, swing: #{prog.swing})"

    @professor.speak(CraneTTS::LESSONS[:intro])
    sleep 3
    @professor.speak(CraneTTS::LESSONS[:swing])

    drums = @drums.generate_drums(prog.tempo, prog.swing, 4)
    return nil unless drums

    @professor.speak(CraneTTS::LESSONS[:pads])
    pads = @pad_gen.generate_dreamy_pad(prog.chords.first, prog.beat_duration * 16)
    return nil unless pads

    @professor.speak(CraneTTS::LESSONS[:drums])
    bass = generate_simple_bass(prog.chords.first, prog.beat_duration * 16)
    return nil unless bass

    @professor.speak(CraneTTS::LESSONS[:mastering])
    mixed = @mixer.mix_tracks(drums, pads, bass, generate_silence(prog.beat_duration * 16))
    return nil unless mixed

    @professor.speak(CraneTTS::LESSONS[:loop])
    output = @master.master_track(mixed)
    [drums, pads, bass, mixed].each { |f| File.delete(f) rescue nil }
    output
  end

  def run_continuous
    puts "🎓 Professor Crane's Neo-Soul Masterclass v73.0-Modular"
    puts "━" * 60
    puts "✅ Modular Architecture: 5 focused modules (~120 lines each)"
    puts "✅ JSON Data Separation: Progressions externalized"
    puts "✅ Auto-cleanup: Temp files removed after each track"
    puts "Press Ctrl+C to stop\n\n"

    track_count = 0
    loop do
      prog_name = PROGRESSIONS.keys.sample
      output = generate_track(prog_name)

      if output
        prog = PROGRESSIONS[prog_name]
        timestamp = Time.now.strftime("%Y%m%d_%H%M%S")
        saved_file = "#{OUTPUT_DIR}/#{prog.name.gsub(/[^a-zA-Z0-9]/, '_')}_#{timestamp}.wav"
        FileUtils.cp(output, saved_file)
        puts "💾 Saved: #{File.basename(saved_file)}"
        play_track(output)
        File.delete(output) rescue nil
      end

      track_count += 1
      cleanup_old_checkpoints if track_count % 3 == 0
      sleep 2
    end
  end

  private

  def generate_simple_bass(chord_name, duration)
    out = "#{CHECKPOINT_DIR}/bass_#{Time.now.to_i}.wav"
    notes = {
      "C" => 261.63, "D" => 293.66, "E" => 329.63, "F" => 349.23,
      "G" => 392.00, "A" => 440.00, "B" => 493.88,
      "Db" => 277.18, "Eb" => 311.13, "Gb" => 369.99, "Ab" => 415.30, "Bb" => 466.16
    }

    root = chord_name[0..1]
    root = chord_name[0] unless notes[root]
    freq = (notes[root] || 261.63) / 2.0

    system("#{SOX_PATH} -n \"#{out}\" synth #{duration} sine #{freq} sine #{freq * 0.5} fade h 0.05 #{duration} 0.1 gain -3 2>/dev/null")
    out
  end

  def generate_silence(duration)
    out = "#{CHECKPOINT_DIR}/silence_#{Time.now.to_i}.wav"
    system("#{SOX_PATH} -n \"#{out}\" synth #{duration} sine 0 vol 0 2>/dev/null")
    out
  end

  def play_track(file)
    win_path = `cygpath -w "#{file}" 2>/dev/null`.chomp
    win_path = file if win_path.empty?
    system("cmd.exe /c start /min wmplayer \"#{win_path}\" 2>/dev/null")
    duration = `soxi -D "#{file}" 2>/dev/null`.to_f rescue 20.0
    sleep duration
  end
end

if __FILE__ == $PROGRAM_NAME
  Signal.trap("INT") do
    puts "\n\n🎓 Dilla signing off. Remember: swing is life!"
    exit 0
  end

  FileUtils.mkdir_p(DillaConstants::CHECKPOINT_DIR)
  FileUtils.mkdir_p(DillaConstants::TTS_CACHE_DIR)
  FileUtils.mkdir_p(DillaConstants::OUTPUT_DIR)

  engine = DillaEngine.new
  engine.run_continuous
end
