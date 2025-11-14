# frozen_string_literal: true

class PadGenerator
  include SoxHelpers

  NOTES = {
    "C" => 261.63, "Db" => 277.18, "D" => 293.66, "Eb" => 311.13,
    "E" => 329.63, "F" => 349.23, "Gb" => 369.99, "G" => 392.00,
    "Ab" => 415.30, "A" => 440.00, "Bb" => 466.16, "B" => 493.88,
    "C#" => 277.18, "D#" => 311.13, "F#" => 369.99, "G#" => 415.30, "A#" => 466.16
  }.freeze

  def generate_dreamy_pad(chord_name, duration)
    output = tempfile("pad_#{chord_name}")
    parsed = parse_chord(chord_name)
    root = NOTES[parsed[:root]] || 261.63
    freqs = chord_freqs(root, parsed[:intervals])
    
    # Generate multiple detuned layers for warmth
    layers = build_warm_layers(freqs, duration)

    # SP-404 style effects chain: vinyl simulator, tape saturation, deep reverb
    # Flying Lotus / Madlib signature sound
    command = sox_cmd([
      "-n \"#{output}\"",
      layers,
      "fade h 0.8 #{duration} 3",
      "overdrive 8 18",                          # Tape saturation (SP-404 style)
      "reverb 60 50 100",                        # Deep reverb (Ableton/FlyLo technique)
      "chorus 0.7 0.9 55 0.4 0.25 2 -s",        # Stereo chorus
      "chorus 0.6 0.8 45 0.3 0.2 2 -t",         # Triangle chorus (layered)
      "equalizer 150 1q 3",                      # Bass warmth
      "equalizer 3000 0.5q -2",                  # Tame digital harshness
      "norm -15",
      "2>/dev/null"
    ].join(" "))

    print "  🎹 Warm Pad (#{chord_name})... "
    system(command)
    puts valid?(output) ? "✓" : "✗"
    output
  end

  private

  def build_warm_layers(freqs, duration)
    layers = []
    
    # Main chord tones
    freqs.each do |f|
      layers << "synth #{duration} sine #{f}"
    end
    
    # Detuned layers for warmth (Moog-style analog drift)
    # Plus/minus 3 cents emulates vintage oscillator instability
    freqs.each do |f|
      detune1 = f * 1.00173
      detune2 = f * 0.99827
      layers << "synth #{duration} sine #{detune1}"
      layers << "synth #{duration} sine #{detune2}"
    end
    
    # Subtle octave harmonics (Minimoog bass character)
    freqs.each do |f|
      layers << "synth #{duration} sine #{f * 2} vol 0.3"
      layers << "synth #{duration} sine #{f * 0.5} vol 0.4"
    end
    
    layers.join(" ")
  end

  def parse_chord(name)
    # Handle C# style notation
    if name.length > 1 && name[1] == '#'
      root = name[0..1]
      quality = name[2..-1].downcase
    elsif name.length > 1 && name[1] == 'b'
      root = name[0..1]
      quality = name[2..-1].downcase
    else
      root = name[0]
      quality = name[1..-1].downcase
    end
    
    intervals = chord_intervals(quality)
    { root: root, intervals: intervals }.freeze
  end

  def chord_intervals(quality)
    case quality
    when "m9", "min9" then [0, 3, 7, 10, 14]
    when "m7", "min7" then [0, 3, 7, 10]
    when "9" then [0, 4, 7, 10, 14]
    when "7sus4" then [0, 5, 7, 10]
    when "maj9" then [0, 4, 7, 11, 14]
    when "maj7" then [0, 4, 7, 11]
    when "7" then [0, 4, 7, 10]
    when "dim7" then [0, 3, 6, 9]
    else [0, 4, 7]
    end
  end

  def chord_freqs(root_freq, intervals)
    intervals.map { |i| root_freq * (2.0 ** (i / 12.0)) }.freeze
  end
end

class DrumGenerator
  include SoxHelpers

  def generate_drums(tempo, swing, bars)
    print "  🥁 Dilla Drums (microtiming)... "
    beat_dur = 60.0 / tempo
    kick = generate_kick
    snare = generate_snare
    hat = generate_hihat

    patterns = bars.times.map do |bar|
      generate_bar_dilla(kick, snare, hat, bar, beat_dur, swing)
    end.compact

    output = tempfile("drums")
    system(sox_cmd("#{patterns.join(" ")} \"#{output}\" 2>/dev/null"))
    cleanup_files(patterns, kick, snare, hat)
    puts valid?(output) ? "✓" : "✗"
    output
  end

  private

  def generate_kick
    out = tempfile("kick")
    system(sox_cmd("-n \"#{out}\" synth 0.3 sine 55 fade h 0.001 0.3 0.15 overdrive 15 gain -3 2>/dev/null"))
    out
  end

  def generate_snare
    out = tempfile("snare")
    system(sox_cmd("-n \"#{out}\" synth 0.18 noise lowpass 3500 highpass 200 fade h 0.001 0.18 0.06 overdrive 5 gain -5 2>/dev/null"))
    out
  end

  def generate_hihat
    out = tempfile("hat")
    system(sox_cmd("-n \"#{out}\" synth 0.04 noise highpass 9000 fade h 0.001 0.04 0.015 gain -10 2>/dev/null"))
    out
  end

  def generate_bar_dilla(kick, snare, hat, bar_num, beat_dur, swing)
    bar_dur = beat_dur * 4
    offset = bar_num * bar_dur
    hits = []

    # Kick pattern with Dilla microtiming (-20ms to +40ms variation)
    [0, 1.5, 2, 3.5].each do |beat|
      t = offset + (beat * beat_dur)
      microtiming = (rand(-20..40) / 1000.0)
      t += microtiming
      hits << pad_sample(kick, t, bar_dur)
    end

    # Snare on 1 and 3 (laid back, -30ms to -10ms behind beat)
    [1, 3].each do |beat|
      t = offset + (beat * beat_dur)
      drag = (rand(-40..-15) / 1000.0)  # Dilla signature laid-back snare
      t += drag
      hits << pad_sample(snare, t, bar_dur)
    end

    # Hi-hats with varying swing (16th notes)
    16.times do |i|
      t = offset + (i * beat_dur * 0.25)
      
      # Apply swing to off-beats
      if i.odd?
        swing_offset = beat_dur * 0.25 * (swing - 0.5)
        t += swing_offset
        
        # Add subtle random microtiming (±15ms)
        microtiming = (rand(-15..15) / 1000.0)
        t += microtiming
      else
        # Even hi-hats stay closer to grid (±5ms)
        microtiming = (rand(-5..5) / 1000.0)
        t += microtiming
      end
      
      hits << pad_sample(hat, t, bar_dur)
    end

    out = tempfile("bar")
    system(sox_cmd("-m #{hits.join(" ")} \"#{out}\" 2>/dev/null"))
    cleanup_files(hits)
    out
  end

  def pad_sample(sample, offset, duration)
    out = tempfile("pad")
    # Ensure offset is never negative
    safe_offset = [offset, 0].max
    system(sox_cmd("\"#{sample}\" \"#{out}\" pad #{safe_offset} 0 trim 0 #{duration} 2>/dev/null"))
    out
  end
end
