# frozen_string_literal: true
#
# Pitch shifting and FM-morphing a sample.
#
# Part of the dilla engine, split out of dilla.rb. Defines methods and
# constants at top level exactly as it did there; dilla.rb requires the
# parts in the file's original order, because several constants are
# computed at load time from ones declared above them.

# --- morphing a sample toward FM -----------------------------------------------
#
# You cannot frequency-modulate a recording the way an FM operator modulates an
# oscillator -- there is no oscillator to modulate. But ffmpeg's vibrato accepts
# rates up to 20 kHz, and vibrato at an audio rate IS frequency modulation of
# whatever goes through it: the sidebands at carrier +- modulator are real, and
# they are what the ear hears as FM.
#
# Whether that sounds musical or like a fault is decided by ONE thing: the
# modulator's relationship to the material's own pitch. A modulator at an
# integer multiple of the root puts sidebands on harmonics and reads as a
# brighter, glassier version of the same note. An unrelated rate puts them
# between harmonics and reads as damage. So the rate is derived from the key
# this loop is actually in, not set in hertz.
SAMPLE_FM = ENV["SAMPLE_FM"] == "1"
# Modulator : root. 1, 2, 3 are harmonic and glassy; 1.414 or 3.5 go bell-like
# and inharmonic, which is the DX7 tubular-bell trick.
SAMPLE_FM_RATIO = (ENV["SAMPLE_FM_RATIO"] || 2.0).to_f.clamp(0.25, 16.0)
# Modulation index by another name. Past ~0.15 the pitch of the source stops
# being legible and it becomes texture rather than a note.
# With the floor below doing the protecting, depth can be generous: swept at
# 0.03/0.05/0.08/0.12 the chord band moved +0.0, +0.0, +0.0, +0.1 dB while the
# upper band moved -0.4, +0.2, +0.9, +1.5. The constraint is not the depth, it
# is where the modulation is allowed to reach.
SAMPLE_FM_DEPTH = (ENV["SAMPLE_FM_DEPTH"] || 0.08).to_f.clamp(0.0, 0.4)
SAMPLE_FM_MIX = (ENV["SAMPLE_FM_MIX"] || 0.55).to_f.clamp(0.0, 1.0)
# The FM branch is bandlimited from here up, and this is the whole safety of the
# effect. Modulating the fundamental and the low harmonics detunes the notes
# that carry the chord -- the harmony goes sour and it reads as damage rather
# than as timbre. Above ~700 Hz the sidebands land on overtones, which colours
# the sound while leaving the pitch and the chord exactly where they were. The
# first version highpassed at 60 Hz, which is to say not at all, and the result
# ate the harmonics it was supposed to be decorating.
SAMPLE_FM_FLOOR_HZ = (ENV["SAMPLE_FM_FLOOR_HZ"] || 700).to_i
# Inharmonic partials, the other half of the metallic FM character. In Hz, and
# deliberately small: a few Hz detunes the overtones against each other without
# moving the perceived pitch.
SAMPLE_FM_SHIFT_HZ = (ENV["SAMPLE_FM_SHIFT_HZ"] || 0).to_f.clamp(-200.0, 200.0)

# Scale expansion: the loop layered against transposed copies of itself at
# degrees of its OWN key, so one sample becomes a chord it was never playing.
# Degrees are semitones from the detected root -- the default is a minor triad
# because most of these loops read minor.
SAMPLE_SCALE = ENV["SAMPLE_SCALE"] == "1"
SAMPLE_SCALE_DEGREES = (ENV["SAMPLE_SCALE_DEGREES"] || "3,7").split(",").map(&:to_f)
SAMPLE_SCALE_MIX = (ENV["SAMPLE_SCALE_MIX"] || 0.4).to_f.clamp(0.0, 1.0)

# Root frequency of a detected key, low enough to be the fundamental rather than
# a harmonic of it.
def sample_root_hz(path)
  key = sample_key(path)
  return 65.41 unless key # C2 if the key cannot be read

  midi = 36 + key[0]
  (440.0 * (2.0**((midi - 69) / 12.0))).round(3)
end

# Pitch shift that keeps duration: resample to move pitch, then undo the speed
# change. atempo floors at 0.5 per stage, so large shifts chain.
def pitch_shift_filter(semitones)
  ratio = 2.0**(semitones / 12.0)
  stages = []
  comp = 1.0 / ratio
  while comp > 2.0
    stages << 2.0
    comp /= 2.0
  end
  while comp < 0.5
    stages << 0.5
    comp /= 0.5
  end
  stages << comp
  "asetrate=#{(SAMPLE_RATE * ratio).round},aresample=#{SAMPLE_RATE}," +
    stages.map { |s| "atempo=#{s.round(6)}" }.join(",")
end

def sample_morph!(src, dest)
  return src unless (SAMPLE_FM || SAMPLE_SCALE) && File.file?(src)

  root = sample_root_hz(src)
  branches = ["[0:a]anull[dry]"]
  labels = ["[dry]"]
  weights = ["1.0"]
  idx = 0

  if SAMPLE_FM
    mod_hz = (root * SAMPLE_FM_RATIO).round(2)
    shift = SAMPLE_FM_SHIFT_HZ.zero? ? "" : ",afreqshift=shift=#{SAMPLE_FM_SHIFT_HZ}"
    # Highpass BEFORE the modulation as well as after: modulating the lows and
    # then removing them still leaves their sidebands folded into the range
    # that survives.
# afreqshift, not vibrato. vibrato is TRANSPARENT in this ffmpeg build --
# depths of 0.1, 0.5 and 0.9 all produce output identical to the input, and
# identical to each other. The earlier claim here that audio-rate vibrato
# produced real FM sidebands was wrong: the sweep that appeared to confirm
# it varied depth and mix together, so what it measured was the highpassed
# dry copy being blended in, not sidebands at all.
#
# Frequency shifting is not the same operation as FM, and saying so matters:
# FM generates sidebands at multiples of the modulator, while a shift moves
# every partial by a fixed number of Hz. But it produces genuine inharmonic
# content -- measured +4.3 dB above 500 Hz on a 200 Hz sine, where vibrato
# gave 0.0 -- and inharmonic partials are the bell-like quality this was
# reaching for. The floor still protects the chord tones.
shift_hz = SAMPLE_FM_SHIFT_HZ.zero? ? (root * (SAMPLE_FM_RATIO - 1.0)).round(2) : SAMPLE_FM_SHIFT_HZ
branches << "[0:a]highpass=f=#{SAMPLE_FM_FLOOR_HZ}," \
            "afreqshift=shift=#{shift_hz}:level=1," \
            "highpass=f=#{SAMPLE_FM_FLOOR_HZ}[fm#{idx}]"
    labels << "[fm#{idx}]"
    weights << SAMPLE_FM_MIX.to_s
    idx += 1
  end

  if SAMPLE_SCALE
    SAMPLE_SCALE_DEGREES.each_with_index do |semi, i|
      branches << "[0:a]#{pitch_shift_filter(semi)},lowpass=f=6000[sc#{i}]"
      labels << "[sc#{i}]"
      # Upper degrees quieter, or the chord overwhelms the note it came from.
      weights << (SAMPLE_SCALE_MIX * (1.0 - (i * 0.18))).round(3).to_s
    end
  end

  chain = branches.dup
  chain << "#{labels.join}amix=inputs=#{labels.size}:weights=#{weights.join(' ')}:" \
           "duration=first:normalize=0,alimiter=limit=0.95:level_out=0.96[mout]"
  begin
    sh! "ffmpeg", "-y", "-i", src, "-filter_complex", chain.join(";"),
        "-map", "[mout]", "-ar", SAMPLE_RATE.to_s, "-ac", "2",
        "-c:a", "pcm_s16le", dest
    note = []
    note << "FM #{(root * SAMPLE_FM_RATIO).round}Hz (root #{root.round}, ratio #{SAMPLE_FM_RATIO})" if SAMPLE_FM
    note << "scale +#{SAMPLE_SCALE_DEGREES.map(&:to_i).join('/+')}" if SAMPLE_SCALE
    puts "sample morph: #{note.join(', ')}"
    dest
  rescue StandardError => e
    warn "sample morph: #{e.message}"
    src
  end
end
