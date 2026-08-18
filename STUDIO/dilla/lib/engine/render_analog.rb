# frozen_string_literal: true
#
# The analog renderer.
#
# Part of the dilla engine, split out of dilla.rb. Defines methods and
# constants at top level exactly as it did there; dilla.rb requires the
# parts in the file's original order, because several constants are
# computed at load time from ones declared above them.

# =============================================================================
# ANALOG RENDERER (dilla_analog.rb)
# =============================================================================

def analog_two_bar_cycle
  (beat_seconds * 4 * 2).round(6)
end

def analog_drum_cycle_events(events)
  cycle = analog_two_bar_cycle
  events.map { |t, *rest| [(t % cycle).round(6), *rest] }
end

def kick_wave(t, v, cycle = analog_two_bar_cycle)
  tc = t.round(6)
  td = "mod(t,#{cycle})"
  "between(#{td},#{tc},#{(t + 0.42).round(6)})*#{v}*0.95*exp(-(#{td}-#{tc})*7.4)*" \
    "sin(2*PI*(45+115*exp(-20*(#{td}-#{tc})))*(#{td}-#{tc}))"
end

def bass_wave(t, v, f, cycle = analog_two_bar_cycle)
  tc = t.round(6)
  td = "mod(t,#{cycle})"
  "between(#{td},#{tc},#{(t + 0.46).round(6)})*#{v}*0.42*exp(-(#{td}-#{tc})*3.2)*sin(2*PI*#{f}*(#{td}-#{tc}))"
end

def analog_section_for_bar(b, total)
  return [:intro, 0.42] if b < 8
  return [:a, 1.00] if b < 24
  return [:a2, 1.00] if b < 40
  return [:break, 0.55] if b < 48
  return [:b, 1.00] if b < 64
  return [:drop, 0.72] if b < 72
  return [:c, 1.00] if b < 88
  [:outro, [0.25, 1.0 - ((b - 88) / [12.0, total - 88.0].max)].max]
end

# PAD_CHORDS entries all carry five voices, so the fixed indices below were safe
# for as long as PAD_CHORDS was the only source. Progression chords are not:
# neo_soul voices as [3, 3, 3, 2, 3, 3, 3, 3], because enrich_progression thins
# and drops roots on purpose. hz[3] on a three-note chord is nil, and nil * 1.122
# is a NoMethodError in the middle of a render.
#
# Widened rather than guarded. A two-note chord under a pad written for five
# does not read as the same part in a new key, it reads as a thinner record, so
# short chords are extended upward by octaves of their own tones until they have
# five. That keeps the pad's density while letting its pitches follow.
ANALOG_PAD_VOICES = 5

def analog_fit_chord(hz)
  voices = Array(hz).map(&:to_f).select(&:positive?).uniq.sort
  return voices if voices.empty? || voices.length >= ANALOG_PAD_VOICES

  # Successive octaves of successive tones: base[0]*2, base[1]*2, base[0]*4 …
  # Doubling the same tone every time -- which the first version did, because
  # `voices.length % voices.length` is always 0 -- produced [100,150,200,200,200]
  # and a chord that is three copies of one note is not five voices.
  base = voices.dup
  tried = 0
  while voices.length < ANALOG_PAD_VOICES && tried < base.length * 6
    candidate = (base[tried % base.length] * (2**(1 + (tried / base.length)))).round(2)
    # Skip an octave the chord already contains: [100,150,200] would otherwise
    # take 100*2 and spend a voice on a unison with the 200 already there.
    voices << candidate unless voices.any? { |v| (v - candidate).abs < 0.5 }
    tried += 1
  end
  voices.sort
end

def analog_rotate_chord(chord, bar_index)
  fitted = analog_fit_chord(chord[:hz])
  return fitted if fitted.empty?

  hz = fitted.rotate((bar_index / 8) % fitted.length)
  extra = case bar_index % 12
          when 0 then hz[0] * 1.067
          when 4 then (hz[2] || hz.last) * 1.414
          when 8 then (hz[3] || hz.last) * 1.122
          end
  extra ? (hz + [extra]) : hz
end

# `chords` overrides PAD_CHORDS when the caller has a progression to offer.
# Same shape either way -- { name:, hz: [...] } -- which is why this is a
# substitution rather than a conversion: PAD_CHORDS was already a hardcoded
# six-chord progression in F minor, so this renderer has always been harmonic,
# just never in the key anything else was in.
def analog_schedule(bar_count, chords = nil)
  pool = (chords && chords.length >= 2) ? chords : PAD_CHORDS
  beat = beat_seconds
  bar_len = beat * 4
  step = bar_len / 16
  events = Hash.new { |h, k| h[k] = [] }
  kick_patterns = [[0, 7, 10, 14], [0, 5, 7, 10, 14], [0, 3, 7, 10, 12, 14], [0, 6, 9, 14]]

  bar_count.times do |b|
    sec, den = analog_section_for_bar(b, bar_count)
    base = b * bar_len
    kp = kick_patterns[(b / 8 + b % 3) % kick_patterns.length].dup
    kp = [0, 3, 6, 7, 10, 12, 14, 15] if b % 16 == 15
    kp = [0, 10] if sec == :intro && b > 2
    kp = [] if sec == :intro && b <= 2
    kp = (b.even? ? [0] : [0, 7]) if sec == :break
    kp = (b.even? ? [0, 10] : [0, 7, 14]) if sec == :drop
    kp = [0] if sec == :outro && b > bar_count - 8 && b % 4 == 0

    kp.each_with_index do |s, i|
      t = base + s * step + [0.000, 0.006, 0.011, -0.004, 0.018][(b + i) % 5]
      events[:kick] << [t, den]
      events[:bass] << [t + 0.023, den, ANALOG_ROOTS[(b / 4 + i) % ANALOG_ROOTS.length]] unless sec == :intro
    end

    [4, 12].each do |s|
      events[:snare] << [base + s * step + [-0.010, -0.006, 0.004, 0.010, 0.017][b % 5], den] unless sec == :intro
    end

    (b.even? ? [6, 11] : [3, 6, 11, 15]).each do |s|
      events[:ghost] << [base + s * step + [-0.014, 0.006, 0.018][(b + s) % 3], den * 0.32] unless [:intro, :drop].include?(sec)
    end

    hats = b % 16 == 7 ? [0, 4, 8, 12] : [0, 2, 4, 6, 8, 10, 12, 14]
    hats = b.even? ? [] : [0, 4, 8, 12] if sec == :break
    hats.each_with_index do |s, i|
      jitter = [-0.004, 0.000, 0.003, 0.006][(b + s) % 4]
      events[:hat] << [base + s * step + (i.odd? ? 0.018 : 0.002) + jitter, den * 0.52]
    end

    events[:open] << [base + 6 * step + 0.008, den * 0.30] if ![:intro, :break].include?(sec) && [1, 3].include?(b % 4)

    if b >= 2 && b % 4 == 0
      chord = analog_rotate_chord(pool[(b / 4) % pool.length], b)
      sustain = 3.2 + (b % 3) * 0.9
      events[:pad] << [base + 0.03, den, chord, sustain]
    end

    if b >= 2 && b % 2 == 0
      chord = analog_rotate_chord(pool[(b / 4 + 3) % pool.length], b)
      events[:chop] << [base + [1, 2, 5, 9, 13][b % 5] * step + [-0.022, 0.0, 0.017][b % 3], den, chord]
    end

    events[:riser] << [base + 2 * beat, 0.13] if [7, 23, 39, 47, 63, 71, 87].include?(b)
    events[:stop] << [base + 3 * beat, 0.18] if [23, 39, 47, 63, 71, 87].include?(b)
  end
  events
end

def analog_pad_expression(t, v, chord, sustain, bar_index)
  hz = chop_hz(chord)
  parts = hz.each_with_index.map do |f, i|
    drift = 1.0 + ((i - 2) * 0.0017) + (Math.sin((bar_index + i) * 1.7) * 0.0009)
    spike = (bar_index % 11 == i ? (ANALOG_CFG[:bad_tune_spike_cents] / 1200.0) : 0.0)
    ff = f * drift * (2.0 ** spike)
    [
      "sin(2*PI*#{ff}*(t-#{t}))",
      "0.55*sin(2*PI*#{ff * 1.004}*(t-#{t}))",
      "0.32*sin(2*PI*#{ff * 2.005}*(t-#{t}))",
      "0.20*sin(2*PI*#{ff * 0.5}*(t-#{t}))",
      "0.11*sin(2*PI*#{ff * 3.0}*(t-#{t}))",
    ].join("+")
  end.join("+")
  "between(t,#{t},#{t + sustain})*#{v}*0.035*exp(-(t-#{t})*0.26)*(0.78+0.22*sin(2*PI*0.23*(t-#{t})))*(#{parts})"
end

def render_analog(destination, bar_count: bars)
  require_tools! "ffmpeg"
  dur = (bar_count * beat_seconds * 4).round(3)
  # Third instance of the same defect: PAD_CHORDS is a fixed six-chord
  # progression in F minor, so analog renders were always in F minor whatever
  # key the track beside them was in.
  analog_chords = if genre_harmony_enabled?
                    begin
                      dilla_progression(dilla_resolve_config[:progression])
                    rescue StandardError
                      nil
                    end
                  end
  dmesg("analog harmony: pads follow #{analog_chords.length} progression chord(s)",
        unit: "anlg0", parent: "dilla0") if analog_chords && analog_chords.length >= 2
  ev = analog_schedule(bar_count, analog_chords)
  cycle = analog_two_bar_cycle

  kick = analog_drum_cycle_events(ev[:kick]).map { |t, v| kick_wave(t, v, cycle) }
  bass = analog_drum_cycle_events(ev[:bass]).map { |t, v, f| bass_wave(t, v, f, cycle) }
  snare = ev[:snare].map { |t, v| "between(t,#{t},#{t + 0.18})*#{v}*0.60*exp(-(t-#{t})*23)" }
  ghost = ev[:ghost].map { |t, v| "between(t,#{t},#{t + 0.09})*#{v}*exp(-(t-#{t})*35)" }
  hat = ev[:hat].map { |t, v| "between(t,#{t},#{t + 0.06})*#{v}*exp(-(t-#{t})*78)" }
  open_hat = ev[:open].map { |t, v| "between(t,#{t},#{t + 0.25})*#{v}*exp(-(t-#{t})*11)" }
  pad = ev[:pad].each_with_index.map { |(t, v, chord, sustain), i| analog_pad_expression(t, v, chord, sustain, i) }
  chop = ev[:chop].map { |t, v, chord| chop_wave(chord, t, v) }
  risers = ev[:riser].map { |t, v| "between(t,#{t},#{t + 2.0})*#{v}*((t-#{t})/2.0)^2" }
  stops = ev[:stop].map { |t, v| "between(t,#{t},#{t + 1.1})*#{v}*exp(-(t-#{t})*2.2)" }

  inputs = [
    *lavfi("aevalsrc='#{expr_sum(kick)}':d=#{dur}:s=#{SAMPLE_RATE}"),
    *lavfi("aevalsrc='#{expr_sum(bass)}':d=#{dur}:s=#{SAMPLE_RATE}"),
    *lavfi("anoisesrc=color=white:r=#{SAMPLE_RATE}:amplitude=0.5:d=#{dur}:seed=#{noise_seed(16)}"),
    *lavfi("anoisesrc=color=pink:r=#{SAMPLE_RATE}:amplitude=0.04:d=#{dur}:seed=#{noise_seed(17)}"),
    *lavfi("aevalsrc='#{expr_sum(pad)}':d=#{dur}:s=#{SAMPLE_RATE}"),
    *lavfi("aevalsrc='#{expr_sum(chop)}':d=#{dur}:s=#{SAMPLE_RATE}"),
    *lavfi("aevalsrc='#{expr_sum(risers + stops)}':d=#{dur}:s=#{SAMPLE_RATE}"),
  ]

  filter = <<~F
    [0:a]aformat=channel_layouts=stereo[k];
    [1:a]aformat=channel_layouts=stereo,lowpass=f=140[bs];
    [2:a]aformat=channel_layouts=stereo,asplit=3[ns][nh][no];
    [ns]volume='#{safe_volume_env(snare + ghost)}':eval=frame,highpass=f=160,bandpass=f=1600:w=2600[sn];
    [nh]volume='#{safe_volume_env(hat)}':eval=frame,highpass=f=6500[hh];
    [no]volume='#{safe_volume_env(open_hat)}':eval=frame,bandpass=f=5600:w=5200[op];
    [4:a]aformat=channel_layouts=stereo,#{DillaAutomation.pad_character_filter(cutoff_hz: ANALOG_CFG[:lowpass_hz], phaser_speed: 0.1, phaser_decay: 0.35)},adelay=#{ANALOG_CFG[:chorus_delay_l_ms]}|#{ANALOG_CFG[:chorus_delay_r_ms]},aecho=0.18:0.22:120:0.22[pad];
    [5:a]aformat=channel_layouts=stereo,highpass=f=120,lowpass=f=5000,aecho=0.18:0.22:90:0.28[chop];
    [6:a]aformat=channel_layouts=stereo,highpass=f=900,lowpass=f=9000[fx];
    [k][bs][sn][hh][op][pad][chop][fx]amix=inputs=8:weights=1.25 0.9 0.9 0.48 0.42 0.95 0.65 0.35:duration=longest[music];
    [3:a]volume=#{ANALOG_CFG[:vinyl_level]},highpass=f=90,lowpass=f=8000[vinyl];
    [music][vinyl]amix=inputs=2:weights=1 0.32:duration=first,
      acompressor=threshold=-18dB:ratio=3.5:attack=25:release=120:makeup=2,
      acrusher=bits=#{ANALOG_CFG[:sp_bits]}:samples=#{ANALOG_CFG[:sp_ratio].round(3)}:mix=0.22,
      aeval='(tanh((val(0)+#{ANALOG_CFG[:tape_dc]})*1.45)-0.072)/0.87|(tanh((val(1)+#{ANALOG_CFG[:tape_dc]})*1.45)-0.072)/0.87',
      highpass=f=30,lowpass=f=12000,equalizer=f=45:t=o:w=1.2:g=1,
      alimiter=level_out=0.96:limit=0.92[out]
  F

  FileUtils.mkdir_p(File.dirname(destination))
  sh! "ffmpeg", "-y", *inputs, "-filter_complex", filter.tr("\n", " "), "-map", "[out]", *codec_for(destination), destination
  normalise_genre_master!(destination, :analog)
  puts "wrote #{destination}"
end

def analog_liveset(destination = File.join(OUTPUT_DIR, "analog_liveset.mp3"), minutes = 12)
  bar_count = [(minutes.to_f * 60.0 / (beat_seconds * 4)).ceil, 64].max
  render_analog(destination, bar_count:)
end
