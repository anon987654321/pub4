# frozen_string_literal: true

class Mixer
  include SoxHelpers

  def mix_tracks(drums, pads, bass, ambient)
    print "  🎚️  Professional Mix... "
    
    # Verify all inputs exist and are valid
    unless drums && valid?(drums) && pads && valid?(pads) && bass && valid?(bass)
      puts "✗ (missing components)"
      return nil
    end
    
    mixed = tempfile("mixed")

    # MPC-style mixer: slight saturation, wide stereo image
    # Balance inspired by J Dilla, Madlib, Flying Lotus techniques
    # Drums: 0.75 (punchy), Pads: 0.45 (warm bed), Bass: 0.65 (solid foundation)
    command = "#{SOX_PATH} -m -v 0.75 \"#{drums}\" -v 0.45 \"#{pads}\" -v 0.65 \"#{bass}\" \"#{mixed}\" gain -1 2>/dev/null"
    
    result = system(command)
    puts valid?(mixed) ? "✓" : "✗"
    valid?(mixed) ? mixed : nil
  end
end

class MasteringChain
  include SoxHelpers

  def master_track(input)
    print "  🎛️  Mastering Chain... "
    output = apply_eq(input)
    output = apply_compression(output) if output
    output = apply_stereo_widening(output) if output
    output = apply_limiter(output) if output
    puts output && valid?(output) ? "✓" : "✗"
    output
  end

  private

  def apply_eq(input)
    temp = tempfile("eq")
    # Crane Song HEDD-style frequency sculpting
    # Based on Sound on Sound mixing guidelines
    command = sox_cmd([
      "\"#{input}\" \"#{temp}\"",
      "highpass 30",                    # Sub-bass control
      "equalizer 80 1q 2.5",            # Bass weight (60-200Hz)
      "equalizer 350 0.8q -1.5",        # Lower mids boxiness reduction
      "equalizer 1500 1.2q 1.8",        # Mids presence and punch
      "equalizer 4500 0.6q 1.2",        # Upper mids definition
      "equalizer 12000 0.5q -0.8",      # Highs air without harshness
      "2>/dev/null"
    ].join(" "))
    system(command)
    valid?(temp) ? temp : nil
  end

  def apply_compression(input)
    temp = tempfile("comp")
    # SP-404 / MPC3000 style compression with tape saturation
    # Adds warmth and glue like classic samplers
    command = sox_cmd([
      "\"#{input}\" \"#{temp}\"",
      "overdrive 3 10",                                      # Triode (2nd harmonics)
      "compand 0.02,0.20 -60,-50,-40,-30,-20,-10,0,-6 2 -90 0.1",  # Soft knee compression
      "overdrive 5 15",                                      # Pentode (3rd harmonics)
      "2>/dev/null"
    ].join(" "))
    system(command)
    cleanup_files(input)
    valid?(temp) ? temp : nil
  end

  def apply_stereo_widening(input)
    temp = tempfile("stereo")
    # Flying Lotus / Ableton style stereo enhancement
    # Oops effect creates phase-coherent width
    command = sox_cmd([
      "\"#{input}\" \"#{temp}\"",
      "oops",
      "2>/dev/null"
    ].join(" "))
    system(command)
    cleanup_files(input)
    valid?(temp) ? temp : nil
  end

  def apply_limiter(input)
    output = tempfile("mastered")
    # Transparent brick-wall limiting at -0.3dB
    # Preserves dynamics while maximizing loudness
    command = sox_cmd([
      "\"#{input}\" \"#{output}\"",
      "compand 0.01,0.10 -60,-40,-30,-20,-10,-6,0,-3 5 -90 0.05",
      "norm -0.3",
      "gain -n -14",
      "2>/dev/null"
    ].join(" "))
    system(command)
    cleanup_files(input)
    output
  end
end
