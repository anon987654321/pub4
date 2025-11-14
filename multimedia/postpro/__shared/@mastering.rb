# frozen_string_literal: true

class Mixer
  def mix_tracks(drums, pads, bass, ambient)
    print "  🎚️  Professional Mix... "
    mixed = tempfile("mixed")
    command = sox_cmd([
      "-m -v 0.8 \"#{drums}\" -v 0.4 \"#{pads}\" -v 0.6 \"#{bass}\" -v 0.1 \"#{ambient}\" \"#{mixed}\"",
      "norm -3",
      "compand 0.05,0.2 -60,-40,-20,-10 4 -90 0.1 2>/dev/null"
    ].join(" "))
    system(command)
    puts valid?(mixed) ? "✓" : "✗"
    mixed
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
    command = sox_cmd([
      "\"#{input}\" \"#{temp}\"",
      "highpass 30",
      "bass 3 80",
      "treble -2 3000",
      "2>/dev/null"
    ].join(" "))
    system(command)
    valid?(temp) ? temp : nil
  end

  def apply_compression(input)
    temp = tempfile("comp")
    command = sox_cmd([
      "\"#{input}\" \"#{temp}\"",
      "compand 0.05,0.2 -60,-50,-40,-30,-20 6 -90 0.1",
      "2>/dev/null"
    ].join(" "))
    system(command)
    cleanup_files(input)
    valid?(temp) ? temp : nil
  end

  def apply_stereo_widening(input)
    temp = tempfile("stereo")
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
    command = sox_cmd([
      "\"#{input}\" \"#{output}\"",
      "compand 0.01,0.1 -60,-40,-10 20 -90 0.05",
      "norm -0.1",
      "gain -n -14",
      "2>/dev/null"
    ].join(" "))
    system(command)
    cleanup_files(input)
    output
  end
end
