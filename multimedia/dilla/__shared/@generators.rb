# frozen_string_literal: true

class PadGenerator
  include SoxHelpers

  NOTES = {
    "C" => 261.63, "Db" => 277.18, "D" => 293.66, "Eb" => 311.13,
    "E" => 329.63, "F" => 349.23, "Gb" => 369.99, "G" => 392.00,
    "Ab" => 415.30, "A" => 440.00, "Bb" => 466.16, "B" => 493.88
  }.freeze

  def generate_dreamy_pad(chord_name, duration)
    output = tempfile("pad_#{chord_name}")
    parsed = parse_chord(chord_name)
    root = NOTES[parsed[:root]] || 261.63
    freqs = chord_freqs(root, parsed[:intervals])
    layers = build_layers(freqs, duration)

    command = sox_cmd([
      "-n \"#{output}\"",
      layers,
      "fade h 0.5 #{duration} 2",
      "reverb 40",
      "chorus 0.6 0.8 45 0.3 0.2 2 -t",
      "norm -12 2>/dev/null"
    ].join(" "))

    print "  🎹 Dreamy Pad (#{chord_name})... "
    system(command)
    puts valid?(output) ? "✓" : "✗"
    output
  end

  private

  def build_layers(freqs, duration)
    freqs.map { |f| "synth #{duration} sine #{f} sine #{f * 2} sine #{f * 0.5}" }.join(" ")
  end

  def parse_chord(name)
    root = name[0] || "C"
    quality = name[1..-1].downcase
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
    print "  🥁 Drums... "
    beat_dur = 60.0 / tempo
    kick = generate_kick
    snare = generate_snare
    hat = generate_hihat

    patterns = bars.times.map do |bar|
      generate_bar(kick, snare, hat, bar, beat_dur, swing)
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
    system(sox_cmd("-n \"#{out}\" synth 0.25 sine 50 fade h 0.001 0.25 0.1 overdrive 20 gain -2 2>/dev/null"))
    out
  end

  def generate_snare
    out = tempfile("snare")
    system(sox_cmd("-n \"#{out}\" synth 0.15 noise lowpass 4000 highpass 300 fade h 0.001 0.15 0.05 gain -4 2>/dev/null"))
    out
  end

  def generate_hihat
    out = tempfile("hat")
    system(sox_cmd("-n \"#{out}\" synth 0.05 noise highpass 8000 fade h 0.001 0.05 0.02 gain -8 2>/dev/null"))
    out
  end

  def generate_bar(kick, snare, hat, bar_num, beat_dur, swing)
    bar_dur = beat_dur * 4
    offset = bar_num * bar_dur
    hits = []

    [0, 1, 2, 3].each do |beat|
      t = offset + (beat * beat_dur)
      hits << pad_sample(kick, t, bar_dur)
    end

    [1, 3].each do |beat|
      t = offset + (beat * beat_dur)
      hits << pad_sample(snare, t, bar_dur)
    end

    16.times do |i|
      t = offset + (i * beat_dur * 0.25)
      t += (beat_dur * 0.1 * swing) if i.odd?
      hits << pad_sample(hat, t, bar_dur)
    end

    out = tempfile("bar")
    system(sox_cmd("-m #{hits.join(" ")} \"#{out}\" 2>/dev/null"))
    cleanup_files(hits)
    out
  end

  def pad_sample(sample, offset, duration)
    out = tempfile("pad")
    system(sox_cmd("\"#{sample}\" \"#{out}\" pad #{offset} 0 trim 0 #{duration} 2>/dev/null"))
    out
  end
end
