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

    # SP-404 style effects chain with aggressive normalization to reduce file size
    command = sox_cmd([
      "-n \"#{output}\"",
      layers,
      "norm -3",                                 # Normalize EARLY to prevent clipping
      "fade h 0.8 #{duration} 3",
      "overdrive 8 18",                          # Tape saturation (SP-404 style)
      "reverb 60 50 100",                        # Deep reverb (Ableton/FlyLo technique)
      "chorus 0.7 0.9 55 0.4 0.25 2 -s",        # Stereo chorus
      "chorus 0.6 0.8 45 0.3 0.2 2 -t",         # Triangle chorus (layered)
      "equalizer 150 1q 3",                      # Bass warmth
      "equalizer 3000 0.5q -2",                  # Tame digital harshness
      "norm -15",                                # Final normalization
      "2>/dev/null"
    ].join(" "))

    print "  🎹 Warm Pad (#{chord_name})... "
    system(command)
    puts valid?(output) ? "✓" : "✗"
    output
  end

  private

  def build_warm_layers(freqs, duration)
    # SoX requires ALL sine waves in a SINGLE synth command for additive synthesis
    # Format: synth <duration> sine freq1 sine freq2 sine freq3 ...
    parts = ["synth #{duration}"]
    
    # Main chord tones
    freqs.each do |f|
      parts << "sine #{f}"
    end
    
    # Detuned layers for warmth (Moog-style analog drift)
    # Plus/minus 3 cents emulates vintage oscillator instability
    freqs.each do |f|
      detune1 = f * 1.00173
      detune2 = f * 0.99827
      parts << "sine #{detune1}"
      parts << "sine #{detune2}"
    end
    
    # Subtle octave harmonics (Minimoog bass character)
    # Note: vol applies to entire output, not per-sine, so skipping for now
    freqs.each do |f|
      parts << "sine #{f * 2}"
      parts << "sine #{f * 0.5}"
    end
    
    parts.join(" ")
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

  GOLDBABY_PATH = "G:/music/samples/goldbaby".freeze
  
  DRUM_STYLES = {
    dilla: { swing: 0.64, kick_offset: 40, snare_offset: -35 },
    flylo: { swing: 0.58, kick_offset: 25, snare_offset: -20 },
    techno: { swing: 0.52, kick_offset: 5, snare_offset: 0 }
  }.freeze

  def generate_drums(tempo, swing, bars)
    style = DRUM_STYLES.keys.sample
    config = DRUM_STYLES[style]
    
    print "  🥁 #{style.to_s.capitalize} Drums (microtiming)... "
    
    case style
    when :dilla
      output = generate_dilla_drums(tempo, config[:swing], bars, config)
    when :flylo
      output = generate_flylo_drums(tempo, config[:swing], bars, config)
    when :techno
      output = generate_techno_drums(tempo, bars, config)
    end
    
    puts output && valid?(output) ? "✓" : "✗"
    output
  end

  private

  def generate_dilla_drums(tempo, swing, bars, config)
    beat_dur = 60.0 / tempo
    kick = generate_kick
    snare = generate_snare
    hat = generate_hihat

    patterns = bars.times.map do |bar|
      generate_bar_dilla(kick, snare, hat, bar, beat_dur, swing, config)
    end.compact

    output = tempfile("drums")
    system(sox_cmd("#{patterns.map{|p| "\"#{p}\""}.join(" ")} \"#{output}\" 2>/dev/null"))
    cleanup_files(patterns, kick, snare, hat)
    output
  end

  def generate_flylo_drums(tempo, swing, bars, config)
    # Flying Lotus: off-grid, layered, glitchy, skips beats randomly
    beat_dur = 60.0 / tempo
    kick = generate_kick
    snare = generate_layered_snare
    hat = generate_hihat

    patterns = bars.times.map do |bar|
      generate_bar_flylo(kick, snare, hat, bar, beat_dur, swing, config)
    end.compact

    output = tempfile("drums_flylo")
    system(sox_cmd("#{patterns.map{|p| "\"#{p}\""}.join(" ")} \"#{output}\" overdrive 8 12 2>/dev/null"))
    cleanup_files(patterns, kick, snare, hat)
    output
  end

  def generate_techno_drums(tempo, bars, config)
    # Industrial techno: 4-on-floor, heavy distortion, sparse claps
    beat_dur = 60.0 / tempo
    kick = generate_heavy_kick
    clap = generate_sparse_clap
    hat = generate_909_hat

    patterns = bars.times.map do |bar|
      generate_bar_techno(kick, clap, hat, bar, beat_dur)
    end.compact

    output = tempfile("drums_techno")
    system(sox_cmd("#{patterns.map{|p| "\"#{p}\""}.join(" ")} \"#{output}\" overdrive 25 35 equalizer 60 2q 4 2>/dev/null"))
    cleanup_files(patterns, kick, clap, hat)
    output
  end

  def generate_bar_dilla(kick, snare, hat, bar_num, beat_dur, swing, config)
    bar_dur = beat_dur * 4
    bar_file = tempfile("bar")
    
    events = []
    
    # Kicks on 1,2,3,4 with Dilla drift (±40ms)
    4.times do |beat|
      offset = rand(-config[:kick_offset]..config[:kick_offset]) / 1000.0
      events << "#{kick} #{beat * beat_dur + offset}"
    end
    
    # Snares on 2,4 with signature drag (-40ms to -15ms)
    [1, 3].each do |beat|
      drag = rand(config[:snare_offset]..-15) / 1000.0
      events << "#{snare} #{beat * beat_dur + drag}"
    end
    
    # Swung hats (8th notes with swing + microtiming)
    8.times do |eighth|
      offset = (eighth % 2 == 1) ? (beat_dur * swing * 0.5) : 0
      jitter = (eighth % 2 == 1) ? rand(-15..15) / 1000.0 : rand(-5..5) / 1000.0
      events << "#{hat} #{(eighth * beat_dur * 0.5) + offset + jitter}"
    end
    
    build_event_bar(events, bar_file, bar_dur)
    bar_file
  end

  def generate_bar_flylo(kick, snare, hat, bar_num, beat_dur, swing, config)
    # FlyLo: off-grid, layered, glitchy
    bar_dur = beat_dur * 4
    bar_file = tempfile("bar_flylo")
    
    events = []
    
    # Kicks: skip beats but ensure at least 2 kicks per bar
    kick_beats = [0, 1, 2, 3].shuffle.take(rand(2..4))
    kick_beats.each do |beat|
      offset = rand(-config[:kick_offset]..config[:kick_offset]) / 1000.0
      events << "#{kick} #{beat * beat_dur + offset}"
    end
    
    # Layered snares: main + ghost
    [1, 3].each do |beat|
      position = beat * beat_dur
      events << "#{snare} #{position + (config[:snare_offset] / 1000.0)}"
      # Ghost snare layer (early, quieter)
      events << "#{snare} #{position - 0.015}" if rand < 0.6
    end
    
    # Irregular hats: skip some but ensure minimum 4 hats
    hat_eighths = (0..7).to_a.shuffle.take(rand(4..6))
    hat_eighths.each do |eighth|
      offset = (eighth % 2 == 1) ? (beat_dur * swing * 0.5) : 0
      jitter = rand(-30..30) / 1000.0
      events << "#{hat} #{(eighth * beat_dur * 0.5) + offset + jitter}"
    end
    
    build_event_bar(events, bar_file, bar_dur)
    bar_file
  end

  def generate_bar_techno(kick, clap, hat, bar_num, beat_dur)
    # Industrial techno: solid 4-on-floor, sparse claps on 2+4, offbeat 909 hats
    bar_dur = beat_dur * 4
    bar_file = tempfile("bar_techno")
    
    events = []
    
    # 4-on-floor kicks (no swing, no variation - industrial precision)
    4.times do |beat|
      events << "#{kick} #{beat * beat_dur}"
    end
    
    # Claps only on 2 and 4 (backbeat)
    [1, 3].each do |beat|
      events << "#{clap} #{beat * beat_dur}"
    end
    
    # 909 hats on offbeats only (classic techno)
    8.times do |eighth|
      next if (eighth % 2) == 0  # Only offbeats
      events << "#{hat} #{eighth * beat_dur * 0.5}"
    end
    
    build_event_bar(events, bar_file, bar_dur)
    bar_file
  end

  def build_event_bar(events, bar_file, bar_dur)
    # Each event is "filepath time_offset"
    return nil if events.nil? || events.empty?
    
    # Need to create silence-padded versions then mix them
    padded_files = events.map.with_index do |event, idx|
      parts = event.split(' ', 2)
      file = parts[0]
      offset = parts[1].to_f
      
      # Skip invalid offsets
      next if offset < 0 || offset > bar_dur
      
      padded = tempfile("padded_#{idx}")
      # Create silence + audio at the right position
      if system(sox_cmd("\"#{file}\" \"#{padded}\" pad #{offset} 2>/dev/null"))
        padded
      else
        nil
      end
    end.compact
    
    return nil if padded_files.empty?
    
    # Mix all padded files together
    quoted_files = padded_files.map { |f| "\"#{f}\"" }.join(" ")
    success = system(sox_cmd("-m #{quoted_files} \"#{bar_file}\" trim 0 #{bar_dur} 2>/dev/null"))
    cleanup_files(padded_files)
    
    success && valid?(bar_file) ? bar_file : nil
  end

  def generate_kick
    out = tempfile("kick")
    # Kick with fundamental + harmonics in ONE synth command
    system(sox_cmd("-n \"#{out}\" synth 0.3 sine 55 sine 110 vol 0.4 sine 220 vol 0.2 sine 330 vol 0.1 fade h 0.001 0.3 0.15 overdrive 15 gain -3 2>/dev/null"))
    out
  end

  def generate_heavy_kick
    # Industrial techno: heavier, more distorted with rich harmonics
    out = tempfile("kick_heavy")
    system(sox_cmd("-n \"#{out}\" synth 0.35 sine 45 sine 90 vol 0.5 sine 180 vol 0.3 sine 270 vol 0.15 fade h 0.001 0.35 0.2 overdrive 30 gain -2 2>/dev/null"))
    out
  end

  def generate_snare
    out = tempfile("snare")
    # White noise with band-pass filtering for realistic snare
    system(sox_cmd("-n \"#{out}\" synth 0.18 noise lowpass 3500 highpass 200 fade h 0.001 0.18 0.06 overdrive 5 gain -5 2>/dev/null"))
    out
  end

  def generate_layered_snare
    # FlyLo style: add some reverb for depth
    out = tempfile("snare_layered")
    system(sox_cmd("-n \"#{out}\" synth 0.2 noise lowpass 3500 highpass 200 fade h 0.001 0.2 0.08 reverb 20 overdrive 5 gain -5 2>/dev/null"))
    out
  end

  def generate_sparse_clap
    # Techno: sparse clap with long reverb
    out = tempfile("clap")
    system(sox_cmd("-n \"#{out}\" synth 0.15 noise highpass 2500 fade h 0.001 0.15 0.05 reverb 80 50 100 gain -6 2>/dev/null"))
    out
  end

  def generate_hihat
    out = tempfile("hat")
    system(sox_cmd("-n \"#{out}\" synth 0.04 noise highpass 9000 fade h 0.001 0.04 0.015 gain -10 2>/dev/null"))
    out
  end

  def generate_909_hat
    # 909 style: brighter, tighter
    out = tempfile("hat_909")
    system(sox_cmd("-n \"#{out}\" synth 0.03 noise highpass 10000 fade h 0.001 0.03 0.01 gain -10 2>/dev/null"))
    out
  end
end

class BassMaker
  include SoxHelpers

  def generate_bass(chord_progression, duration)
    print "  🎸 Walking Bass... "
    bass_notes = chord_progression.map { |chord_name| extract_root_note(chord_name) }
    output = generate_bass_line(bass_notes, duration / bass_notes.size)
    puts output && valid?(output) ? "✓" : "✗"
    output
  end

  private

  def extract_root_note(chord_name)
    root = chord_name[0]
    root += chord_name[1] if chord_name.length > 1 && ['#', 'b'].include?(chord_name[1])
    NOTES[root] || 130.81
  end

  def generate_bass_line(frequencies, note_duration)
    output = tempfile("bass")
    
    notes = frequencies.map.with_index do |freq, i|
      position = i * note_duration
      "synth #{note_duration} sine #{freq} fade h 0.1 #{note_duration} 0.2"
    end

    command = sox_cmd([
      "-n \"#{output}\"",
      notes.join(" : newfile : "),
      "overdrive 10 20",
      "norm -18",
      "2>/dev/null"
    ].join(" "))

    system(command)
    valid?(output) ? output : nil
  end
end
