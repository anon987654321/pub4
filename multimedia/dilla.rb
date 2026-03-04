#!/usr/bin/env ruby
# frozen_string_literal: true
# Dilla - J Dilla Music Generation & Playback
# Version: 5.0.0 - Consolidated per master.json (zero sprawl)
#
# Usage:
#   ruby dilla.rb              # Interactive menu
#   ruby dilla.rb --generate   # Generate all audio
#   ruby dilla.rb --play       # Play chords continuously
#   ruby dilla.rb --quick      # Quick generation (5 progressions)

require "json"
require "fileutils"

# ============================================================================
# CONFIGURATION
# ============================================================================

BASE_DIR = "G:/pub/multimedia/dilla"
SOX = "#{BASE_DIR}/effects/sox/sox.exe"
CHORDS_DIR = "#{BASE_DIR}/chords"
DRUMS_DIR = "#{BASE_DIR}/drums"
BASS_DIR = "#{BASE_DIR}/bass"
FINAL_DIR = "#{BASE_DIR}/final"

FileUtils.mkdir_p([CHORDS_DIR, DRUMS_DIR, BASS_DIR, FINAL_DIR])

# FM Synthesis FX Presets
FX_PRESETS = {
  warm_tape: "compand 0.3,1 -inf,-70,-60,-20 -5 -90 0.2 reverb 35 50 80 norm -2 dither -s",
  lofi_dream: "compand 0.05,0.2 -inf,-70,-50,-20 -6 -90 0.1 reverb 40 60 90 norm -2 dither -s",
  dilla_butter: "compand 0.1,0.3 -inf,-70,-55,-20 -6 -90 0.15 reverb 30 50 85 norm -2 dither -s",
  analog_lush: "compand 0.2,0.4 -inf,-65,-50,-30 -5 -90 0.18 reverb 45 60 95 norm -2 dither -s"
}

# Hall of Fame Chord Progressions
PROGRESSIONS = {
  dilla_life: {
    name: "J Dilla 'Life'", tempo: 90, duration: 2.0, fx: :dilla_butter,
    chords: [
      { name: 'Bbm9', freqs: [116.54, 174.61, 220.00, 261.63, 329.63] },
      { name: 'C7', freqs: [130.81, 164.81, 196.00, 233.08, 293.66] },
      { name: 'Fm9', freqs: [174.61, 207.65, 261.63, 311.13, 392.00] },
      { name: 'Bbm9', freqs: [116.54, 174.61, 220.00, 261.63, 329.63] }
    ]
  },
  neo_soul: {
    name: "Neo-Soul Classic", tempo: 90, duration: 2.0, fx: :warm_tape,
    chords: [
      { name: 'Cmaj9', freqs: [130.81, 164.81, 196.00, 246.94, 329.63] },
      { name: 'Am11', freqs: [110.00, 164.81, 220.00, 261.63, 329.63] },
      { name: 'Fmaj13', freqs: [174.61, 220.00, 261.63, 329.63, 440.00] },
      { name: 'G13sus', freqs: [196.00, 261.63, 293.66, 392.00, 493.88] }
    ]
  },
  dreamscape: {
    name: "Dilla Dreamscape", tempo: 85, duration: 2.5, fx: :lofi_dream,
    chords: [
      { name: 'Ebmaj9', freqs: [155.56, 196.00, 233.08, 293.66, 369.99] },
      { name: 'Cm9', freqs: [130.81, 155.56, 196.00, 233.08, 293.66] },
      { name: 'Abmaj13', freqs: [207.65, 261.63, 311.13, 415.30, 523.25] },
      { name: 'Bb13sus', freqs: [233.08, 311.13, 349.23, 466.16, 587.33] }
    ]
  },
  floating: {
    name: "Floating Rhodes", tempo: 92, duration: 2.0, fx: :analog_lush,
    chords: [
      { name: 'Dmaj9', freqs: [146.83, 185.00, 220.00, 277.18, 369.99] },
      { name: 'Bm11', freqs: [123.47, 185.00, 246.94, 293.66, 369.99] },
      { name: 'Gmaj9#11', freqs: [196.00, 246.94, 293.66, 392.00, 493.88] },
      { name: 'A13sus', freqs: [220.00, 293.66, 329.63, 440.00, 554.37] }
    ]
  },
  soulquarian: {
    name: "Soulquarian Butter", tempo: 96, duration: 2.0, fx: :dilla_butter,
    chords: [
      { name: 'Fmaj9', freqs: [174.61, 220.00, 261.63, 329.63, 440.00] },
      { name: 'Dm11', freqs: [146.83, 220.00, 293.66, 349.23, 440.00] },
      { name: 'Bbmaj13', freqs: [233.08, 293.66, 349.23, 466.16, 587.33] },
      { name: 'C13', freqs: [130.81, 164.81, 196.00, 246.94, 329.63] }
    ]
  },
  donut_shop: {
    name: "Donut Shop Dreams", tempo: 82, duration: 2.5, fx: :lofi_dream,
    chords: [
      { name: 'Amaj9', freqs: [110.00, 138.59, 164.81, 207.65, 277.18] },
      { name: 'F#m11', freqs: [92.50, 138.59, 185.00, 220.00, 277.18] },
      { name: 'Dmaj9', freqs: [146.83, 185.00, 220.00, 277.18, 369.99] },
      { name: 'E13sus', freqs: [164.81, 220.00, 246.94, 329.63, 415.30] }
    ]
  },
  slum_village: {
    name: "Slum Village Glow", tempo: 98, duration: 2.0, fx: :warm_tape,
    chords: [
      { name: 'Gmaj9', freqs: [196.00, 246.94, 293.66, 369.99, 493.88] },
      { name: 'Em11', freqs: [164.81, 246.94, 329.63, 392.00, 493.88] },
      { name: 'Cmaj13', freqs: [130.81, 164.81, 196.00, 261.63, 349.23] },
      { name: 'D13sus', freqs: [146.83, 196.00, 220.00, 293.66, 369.99] }
    ]
  },
  ethiojazz: {
    name: "Ethiojazz Nights", tempo: 80, duration: 2.5, fx: :analog_lush,
    chords: [
      { name: 'Dm9(b5)', freqs: [146.83, 174.61, 207.65, 261.63, 329.63] },
      { name: 'Gm11', freqs: [196.00, 293.66, 392.00, 466.16, 587.33] },
      { name: 'Ebmaj7#11', freqs: [155.56, 196.00, 246.94, 311.13, 415.30] },
      { name: 'Am7b13', freqs: [110.00, 130.81, 164.81, 207.65, 261.63] }
    ]
  },
  ahmad_jamal: {
    name: "Ahmad Jamal 'Awakening'", tempo: 88, duration: 2.2, fx: :dilla_butter,
    chords: [
      { name: 'Emaj7', freqs: [164.81, 207.65, 246.94, 311.13] },
      { name: 'G#m7', freqs: [207.65, 246.94, 311.13, 369.99] },
      { name: 'C#m7', freqs: [138.59, 164.81, 207.65, 246.94] },
      { name: 'F#9', freqs: [92.50, 116.54, 138.59, 174.61, 220.00] }
    ]
  },
  isley_brothers: {
    name: "Isley Brothers Style", tempo: 92, duration: 2.0, fx: :analog_lush,
    chords: [
      { name: 'Gbmaj9', freqs: [185.00, 233.08, 277.18, 349.23, 466.16] },
      { name: 'Ebm11', freqs: [155.56, 233.08, 311.13, 369.99, 466.16] },
      { name: 'Abm9', freqs: [207.65, 246.94, 311.13, 369.99, 493.88] },
      { name: 'Db13', freqs: [138.59, 174.61, 207.65, 261.63, 349.23] }
    ]
  }
}

# ============================================================================
# CORE AUDIO ENGINE
# ============================================================================

def sox(*args)
  cmd = "\"#{SOX}\" #{args.join(' ')}"
  system(cmd)
end

def cleanup(*files)
  files.each { |f| File.delete(f) rescue nil if File.exist?(f) }
end

# FM Synthesis: 3-layer (sawtooth + square + sine)
def generate_chord(freqs, duration, output)
  voices = freqs.each_with_index.map do |freq, i|
    sox("-n saw#{i}.wav synth #{duration} sawtooth #{freq} gain -18")
    sox("-n sqr#{i}.wav synth #{duration} square #{freq} gain -20")
    sox("-n sin#{i}.wav synth #{duration} sine #{freq} gain -16")
    file = "v#{i}.wav"
    sox("-m saw#{i}.wav sqr#{i}.wav sin#{i}.wav #{file}")
    cleanup("saw#{i}.wav", "sqr#{i}.wav", "sin#{i}.wav")
    file
  end
  sox("-m #{voices.join(' ')} #{output}")
  cleanup(*voices)
end

def apply_fx(input, output, preset_name)
  preset = FX_PRESETS[preset_name] || FX_PRESETS[:dilla_butter]
  sox("#{input} #{output} #{preset}")
end

# ============================================================================
# GENERATION
# ============================================================================

def generate_chords(quick_mode: false)
  puts "\n🎹 Generating J Dilla Chord Progressions..."
  puts "=" * 60

  progs = quick_mode ? PROGRESSIONS.first(5) : PROGRESSIONS

  progs.each do |key, prog|
    puts "\n#{prog[:name]} (#{prog[:fx]})"

    chord_files = prog[:chords].map.with_index do |chord, i|
      file = "c#{i}.wav"
      generate_chord(chord[:freqs], prog[:duration], file)
      print "  #{chord[:name]}... "
      file
    end
    puts

    sox("#{chord_files.join(' ')} #{chord_files.join(' ')} temp.wav")
    output = "#{CHORDS_DIR}/#{key}.wav"
    apply_fx("temp.wav", output, prog[:fx])
    cleanup("temp.wav", *chord_files)
    puts "  ✓ #{output}"
  end

  puts "\n✓ Generated #{progs.size} progressions"
end

# ============================================================================
# PLAYBACK
# ============================================================================

def play_chords_continuous
  chord_files = Dir["#{CHORDS_DIR}/*.wav"].sort

  if chord_files.empty?
    puts "\n⚠️  No chord files found. Generate first with --generate"
    return
  end

  puts "\n🎵 Playing Dilla chords continuously..."
  puts "📂 Files: #{chord_files.size}"
  puts "🔄 Press Ctrl+C to stop\n\n"

  sox("#{chord_files.join(' ')} -t waveaudio -d repeat 999")
end

def play_single_progression(key)
  file = "#{CHORDS_DIR}/#{key}.wav"

  unless File.exist?(file)
    puts "\n⚠️  File not found: #{file}"
    puts "Available progressions: #{PROGRESSIONS.keys.join(', ')}"
    return
  end

  puts "\n🎵 Playing: #{PROGRESSIONS[key][:name]}"
  sox("#{file} -t waveaudio -d")
end

# ============================================================================
# INTERACTIVE MENU
# ============================================================================

def show_menu
  puts "\n" + "=" * 60
  puts "🎹 DILLA - J Dilla Music Generator & Player"
  puts "=" * 60
  puts
  puts "1. Generate All Chords (#{PROGRESSIONS.size} progressions, ~5-8 min)"
  puts "2. Generate Quick Test (5 progressions, ~2 min)"
  puts "3. Play All Chords Continuously (loop)"
  puts "4. Play Single Progression"
  puts "5. List Available Progressions"
  puts "6. Exit"
  puts
  print "Choose [1-6]: "
  gets.chomp
end

def list_progressions
  puts "\n📋 Available Progressions:"
  puts "-" * 60
  PROGRESSIONS.each do |key, prog|
    exists = File.exist?("#{CHORDS_DIR}/#{key}.wav") ? "✓" : "✗"
    puts "#{exists} #{key.to_s.ljust(20)} - #{prog[:name]} (#{prog[:tempo]} BPM)"
  end
end

def interactive_mode
  loop do
    choice = show_menu

    case choice
    when "1"
      generate_chords
    when "2"
      generate_chords(quick_mode: true)
    when "3"
      play_chords_continuous
    when "4"
      list_progressions
      print "\nEnter progression key: "
      key = gets.chomp.to_sym
      play_single_progression(key)
    when "5"
      list_progressions
    when "6", "q", "quit", "exit"
      puts "\n👋 Goodbye!"
      exit 0
    else
      puts "\n⚠️  Invalid choice. Try again."
    end
  end
end

# ============================================================================
# CLI
# ============================================================================

if __FILE__ == $PROGRAM_NAME
  case ARGV[0]
  when "--generate", "-g"
    generate_chords
  when "--quick", "-q"
    generate_chords(quick_mode: true)
  when "--play", "-p"
    play_chords_continuous
  when "--list", "-l"
    list_progressions
  when "--help", "-h"
    puts <<~HELP
      Dilla - J Dilla Music Generator & Player

      Usage:
        ruby dilla.rb              # Interactive menu
        ruby dilla.rb --generate   # Generate all progressions
        ruby dilla.rb --quick      # Quick test (5 progressions)
        ruby dilla.rb --play       # Play continuously
        ruby dilla.rb --list       # List progressions

      Features:
        - 10 iconic J Dilla chord progressions
        - FM synthesis (sawtooth + square + sine)
        - Hall of Fame FX presets
        - Continuous playback mode
    HELP
  else
    interactive_mode
  end
end
