#!/usr/bin/env ruby
# Burst - Industrial Techno Generator
#
# Pure SoX synthesis for aggressive Berghain-style industrial techno
# No FluidSynth, no external samples - just raw waveform synthesis
#
# Usage:
#   ruby multimedia/burst.rb                           # Default: industrial/berghain_135bpm.wav
#   ruby multimedia/burst.rb --out custom.wav          # Custom output path
#   ruby multimedia/burst.rb --rate 140                # Custom BPM (default: 135)
#   ruby multimedia/burst.rb --bars 8                  # Custom length in bars (default: 16)

require "fileutils"
require "optparse"

# ============================================================================
# CONFIGURATION
# ============================================================================

# Cross-platform SoX detection (Cygwin/OpenBSD/Linux friendly)
def find_sox
  # Try common locations
  candidates = [
    "sox",                                            # System PATH
    "/usr/local/bin/sox",                             # OpenBSD
    "/usr/bin/sox",                                   # Linux
    File.join(__dir__, "dilla", "effects", "sox", "sox.exe"),  # Cygwin relative
    "G:/pub/dilla/effects/sox/sox.exe"                # Absolute Cygwin
  ]

  candidates.each do |path|
    if system("which #{path} > /dev/null 2>&1") || File.exist?(path)
      return path
    end
  end

  # Fallback to system sox
  "sox"
end

SOX = find_sox

# ============================================================================
# OPTIONS PARSING
# ============================================================================

options = {
  output: "industrial/berghain_135bpm.wav",
  rate: 135,
  bars: 16
}

OptionParser.new do |opts|
  opts.banner = "Usage: ruby multimedia/burst.rb [options]"

  opts.on("--out FILE", "Output file path (default: industrial/berghain_135bpm.wav)") do |v|
    options[:output] = v
  end

  opts.on("--rate BPM", Integer, "Tempo in BPM (default: 135)") do |v|
    options[:rate] = v
  end

  opts.on("--bars N", Integer, "Length in bars (default: 16)") do |v|
    options[:bars] = v
  end

  opts.on("-h", "--help", "Show this help message") do
    puts opts
    exit
  end
end.parse!

OUTPUT_FILE = options[:output]
TEMPO = options[:rate]
BARS = options[:bars]

# ============================================================================
# UTILITIES
# ============================================================================

def sox(cmd)
  full_cmd = "#{SOX} #{cmd}"
  success = system(full_cmd)
  unless success
    puts "Warning: SoX command failed: #{full_cmd}"
  end
  success
end

def cleanup(*files)
  files.each do |f|
    next unless File.exist?(f)
    3.times do
      begin
        File.delete(f)
        break
      rescue Errno::EBUSY, Errno::EACCES
        sleep 0.1
      end
    end
  end
end

# ============================================================================
# DRUM SYNTHESIS - INDUSTRIAL STYLE
# ============================================================================

def make_industrial_kick
  # Heavy, distorted 909-style kick with sub bass
  sox("-n _kick.wav synth 0.22 sine 50 fade h 0.001 0.22 0.10 overdrive 25 gain -2")
  "_kick.wav"
end

def make_industrial_snare
  # Aggressive snare with metallic ring
  sox("-n _snare.wav synth 0.15 noise lowpass 5000 highpass 300 fade h 0.001 0.15 0.05 overdrive 20 gain -4")
  "_snare.wav"
end

def make_industrial_hat
  # Sharp closed hi-hat
  sox("-n _hat.wav synth 0.05 noise highpass 8000 fade h 0.001 0.05 0.015 gain -10")
  "_hat.wav"
end

def make_industrial_clap
  # Double-hit industrial clap
  sox("-n _clap1.wav synth 0.08 noise lowpass 3000 highpass 800 fade h 0.001 0.08 0.03 gain -8")
  sox("-n _clap2.wav synth 0.08 noise lowpass 3000 highpass 800 fade h 0.001 0.08 0.03 gain -10")
  sox("_clap2.wav _clap2_delayed.wav pad 0.015 0")
  sox("_clap1.wav _clap2_delayed.wav _clap.wav")
  cleanup("_clap1.wav", "_clap2.wav", "_clap2_delayed.wav")
  "_clap.wav"
end

def make_industrial_tom
  # Low tom hit for fills
  sox("-n _tom.wav synth 0.18 sine 80 fade h 0.001 0.18 0.08 overdrive 12 gain -5")
  "_tom.wav"
end

# ============================================================================
# PATTERN GENERATION - BERGHAIN STYLE
# ============================================================================

def generate_industrial_techno(tempo, bars)
  beat_sec = 60.0 / tempo
  bar_sec = beat_sec * 4
  total_sec = bar_sec * bars

  puts "Generating industrial techno pattern..."
  puts "  Tempo: #{tempo} BPM"
  puts "  Length: #{bars} bars (#{total_sec.round(2)}s)"

  # Create samples
  kick = make_industrial_kick
  snare = make_industrial_snare
  hat = make_industrial_hat
  clap = make_industrial_clap
  tom = make_industrial_tom

  # Four-on-the-floor kick pattern
  kick_seq = []
  bars.times do |bar|
    4.times do |beat|
      offset = bar * bar_sec + beat * beat_sec
      sox("#{kick} _k#{bar}_#{beat}.wav pad #{offset} 0")
      kick_seq << "_k#{bar}_#{beat}.wav"
    end
  end

  # Snare/clap on 2 and 4
  snare_seq = []
  bars.times do |bar|
    base = bar * bar_sec
    # Beat 2 (snare)
    sox("#{snare} _s#{bar}_2.wav pad #{base + beat_sec * 1} 0")
    snare_seq << "_s#{bar}_2.wav"
    # Beat 4 (clap layered with snare)
    sox("#{snare} _s#{bar}_4a.wav pad #{base + beat_sec * 3} 0 gain -1")
    sox("#{clap} _s#{bar}_4b.wav pad #{base + beat_sec * 3} 0")
    snare_seq << "_s#{bar}_4a.wav"
    snare_seq << "_s#{bar}_4b.wav"
  end

  # Hi-hat on every 16th note with dynamics
  hat_seq = []
  bars.times do |bar|
    16.times do |sixteenth|
      offset = bar * bar_sec + sixteenth * (beat_sec / 4)
      # Accent on beats and 16th note 8 (offbeat)
      dyn = if sixteenth % 4 == 0
              -2  # On-beat accent
            elsif sixteenth == 8
              -3  # Mid-bar accent
            else
              -8  # Ghost notes
            end
      sox("#{hat} _h#{bar}_#{sixteenth}.wav pad #{offset} 0 gain #{dyn}")
      hat_seq << "_h#{bar}_#{sixteenth}.wav"
    end
  end

  # Add tom fills every 4 bars
  tom_seq = []
  (bars / 4).times do |section|
    bar = section * 4 + 3  # Last bar of each 4-bar section
    base = bar * bar_sec
    # Triple tom hit leading into next section
    [3.0, 3.5, 3.75].each_with_index do |beat_pos, idx|
      offset = base + beat_pos * beat_sec
      sox("#{tom} _t#{bar}_#{idx}.wav pad #{offset} 0 gain -3")
      tom_seq << "_t#{bar}_#{idx}.wav"
    end
  end

  puts "Mixing layers..."

  # Mix individual layers with padding
  sox("-m #{kick_seq.join(' ')} _kicks.wav pad 0 #{total_sec}")
  sox("-m #{snare_seq.join(' ')} _snares.wav pad 0 #{total_sec}")
  sox("-m #{hat_seq.join(' ')} _hats.wav pad 0 #{total_sec}")
  sox("-m #{tom_seq.join(' ')} _toms.wav pad 0 #{total_sec}") unless tom_seq.empty?

  # Final master with industrial processing
  layers = ["_kicks.wav", "_snares.wav", "_hats.wav"]
  layers << "_toms.wav" if File.exist?("_toms.wav")

  puts "Mastering..."

  # Aggressive mastering chain for industrial sound
  sox("-m #{layers.join(' ')} _premix.wav gain -n -1")
  sox("_premix.wav _compressed.wav compand 0.01,0.15 -60,-60,-20,-15,-10,-10,0,-6 -3 0 0.02")
  sox("_compressed.wav _eq.wav equalizer 60 1q +4 equalizer 120 0.7q +2 equalizer 8000 1.5q +3")
  sox("_eq.wav _final.wav overdrive 8 gain -n -1")

  # Ensure output directory exists
  output_dir = File.dirname(OUTPUT_FILE)
  FileUtils.mkdir_p(output_dir) unless output_dir == "." || File.exist?(output_dir)

  # Final output
  sox("_final.wav #{OUTPUT_FILE}")

  # Cleanup
  cleanup(*kick_seq, *snare_seq, *hat_seq, *tom_seq)
  cleanup("_kicks.wav", "_snares.wav", "_hats.wav", "_toms.wav")
  cleanup("_premix.wav", "_compressed.wav", "_eq.wav", "_final.wav")
  cleanup(kick, snare, hat, clap, tom)

  puts "\n[+] Generated: #{OUTPUT_FILE}"
  puts "  Duration: #{total_sec.round(2)}s (#{bars} bars at #{tempo} BPM)"
end

# ============================================================================
# MAIN
# ============================================================================

if __FILE__ == $PROGRAM_NAME
  puts "\n" + ("=" * 70)
  puts "BURST - Industrial Techno Generator"
  puts "=" * 70
  puts ""

  generate_industrial_techno(TEMPO, BARS)

  puts "\n" + ("=" * 70)
  puts "COMPLETE"
  puts "=" * 70
  puts ""
end
