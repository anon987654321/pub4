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
  include SoxHelpers

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
    puts "\n🎵 #{prog.name} (#{prog.tempo} BPM, swing: #{(prog.swing * 100).round}%)"

    # Generate all elements first
    drums = @drums.generate_drums(prog.tempo, prog.swing, 8)
    return nil unless drums

    # Generate pads cycling through chord progression
    pad_files = []
    4.times do |i|
      chord = prog.chords[i % prog.chords.length]
      pad = @pad_gen.generate_dreamy_pad(chord, prog.beat_duration * 8)
      pad_files << pad if pad
    end
    
    combined_pads = tempfile("combined_pads")
    system("#{SOX_PATH} #{pad_files.join(" ")} \"#{combined_pads}\" 2>/dev/null")
    
    # Don't cleanup pad files until after we check combined_pads
    return nil unless valid?(combined_pads)
    cleanup_files(pad_files)

    # Generate walking bassline
    bass = generate_walking_bass(prog.bassline, prog.beat_duration * 32)
    return nil unless bass

    # Mix all elements - DON'T cleanup until after mixing
    silence = generate_silence(prog.beat_duration * 32)
    mixed = @mixer.mix_tracks(drums, combined_pads, bass, silence)
    
    # Now we can cleanup since we're done with source files
    cleanup_files(silence)
    
    return nil unless mixed && valid?(mixed)

    # Master the track
    output = @master.master_track(mixed)
    
    # Final cleanup
    cleanup_files(drums, combined_pads, bass, mixed)
    
    # Play TTS narration OVER the beat
    if output && valid?(output)
      Thread.new do
        sleep 1
        @professor.speak(CraneTTS::LESSONS[:intro])
        sleep 8
        @professor.speak(CraneTTS::LESSONS[:chord_theory])
        sleep 8
        @professor.speak(CraneTTS::LESSONS[:microtiming])
        sleep 8
        @professor.speak(CraneTTS::LESSONS[:swing])
        sleep 8
        @professor.speak(CraneTTS::LESSONS[:pads])
        sleep 8
        @professor.speak(CraneTTS::LESSONS[:bass])
        sleep 8
        @professor.speak(CraneTTS::LESSONS[:complete])
      end
    end
    
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
        filename = "#{prog.name.gsub(/[^a-zA-Z0-9]/, '_')}_#{timestamp}.wav"
        saved_file = File.join(Dir.pwd, filename)
        FileUtils.cp(output, saved_file)
        puts "💾 Saved: #{filename}"
        play_track(output)
        File.delete(output) rescue nil
      end

      track_count += 1
      cleanup_old_checkpoints if track_count % 3 == 0
      sleep 2
    end
  end

  private

  def generate_walking_bass(bassline, duration)
    out = "#{CHECKPOINT_DIR}/bass_#{Time.now.to_i}.wav"
    notes = {
      "C" => 130.81, "D" => 146.83, "E" => 164.81, "F" => 174.61,
      "G" => 196.00, "A" => 220.00, "B" => 246.94,
      "C#" => 138.59, "D#" => 155.56, "F#" => 184.99, "G#" => 207.65, "A#" => 233.08,
      "Db" => 138.59, "Eb" => 155.56, "Gb" => 184.99, "Ab" => 207.65, "Bb" => 233.08
    }

    # Calculate note duration
    note_dur = duration / bassline.length.to_f
    
    # Generate each bass note
    bass_notes = []
    bassline.each_with_index do |note, i|
      freq = notes[note] || 130.81
      note_file = tempfile("bass_note_#{i}")
      
      # Fingered electric bass with slight pitch envelope
      system("#{SOX_PATH} -n \"#{note_file}\" synth #{note_dur} sine #{freq} sine #{freq * 2} vol 0.3 sine #{freq * 0.5} vol 0.4 fade h 0.01 #{note_dur} 0.08 overdrive 8 gain -4 2>/dev/null")
      bass_notes << note_file
    end
    
    # Concatenate bass notes
    system("#{SOX_PATH} #{bass_notes.join(" ")} \"#{out}\" 2>/dev/null")
    cleanup_files(bass_notes)
    out
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
