# frozen_string_literal: true
#
# Tape and console on the master: hysteresis, tilt, mono bass, drone, tape stop.
#
# Part of the dilla engine, split out of dilla.rb. Defines methods and
# constants at top level exactly as it did there; dilla.rb requires the
# parts in the file's original order, because several constants are
# computed at load time from ones declared above them.

# Real tape hysteresis, applied to the finished master.
#
# Everything else in this engine that saturates is memoryless -- output is a
# function of the current sample alone, so the transfer curve is a single line
# and the same input always gives the same output. Tape is path-dependent: the
# curve is a loop, and the output at a given level differs depending on whether
# the signal arrived there rising or falling. Verified on a sine through this
# model: at input 0.0 the output is 0.0 on the way up and +0.46 on the way down.
# No waveshaper produces that at any setting, which is the difference between
# adding harmonics and sounding like a machine.
#
# Ruby per-sample DSP is slow, so this is opt-in and reports its cost.
# Default 0.16 (drive 1.48), not 0. A Jiles-Atherton magnetisation model sat
# in lib/ fully built and switched off, so nothing rendered by this engine
# had ever been through it. Tape character was being asked of an EQ curve.
TAPE_HYSTERESIS = (ENV["TAPE_HYSTERESIS"] || 0.16).to_f.clamp(0.0, 1.0)
# 0.6 ms of Ornstein-Uhlenbeck wow. Real wow is subtle — enough that held
# notes are never quite steady, not enough to read as an effect.
TAPE_WOW_MS = (ENV["TAPE_WOW_MS"] || 0.6).to_f.clamp(0.0, 8.0)
# 1.0 = original JA loop. Lower = less bias current, wider hysteresis.
TAPE_BIAS = (ENV["TAPE_BIAS"] || 1.0).to_f.clamp(0.0, 1.0)
# Spacing/loss filter in front of the magnetisation, Hz. 0 is off — tape is
# not full-bandwidth into oxide, but turning this on by default would retone
# every existing render. 14000 is the analog starting point.
TAPE_LOSS_HZ = (ENV["TAPE_LOSS_HZ"] || 0).to_f.clamp(0.0, 20_000.0)

# Per-channel console strip. See lib/console_strip.rb for why this is per
# channel and not on the master, and for the harmonic measurements.
#
# CONSOLE_STRIP is the wet amount, 0 disables. Each bus passes its own
# instance with its own seed, so the drums and the pads are coloured by
# different "hardware" rather than by one shared curve -- which is the whole
# point, and is not reproducible by running the same stage on the mix.
# 0.22. Left and right run as separate instances one seed apart, which is the
# whole reason this exists — see the note below on why it is not mono.
CONSOLE_STRIP = (ENV["CONSOLE_STRIP"] || 0.22).to_f.clamp(0.0, 1.0)

# Left and right run as separate instances, offset by one seed. On a desk a
# stereo pair IS two channels, built to the same design and measuring
# differently, and the small mismatch between them is a large part of why a
# console sounds wide. Processing mono and re-widening -- the approach
# tape_hysteresis! takes, correctly, because magnetisation is not a stereo
# phenomenon -- would throw that away here, where it is the effect.
def console_strip!(path, seed: 1, amount: CONSOLE_STRIP)
  return path unless amount.positive? && File.file?(path)

  # ../console_strip, not lib/console_strip: require_relative resolves against
  # the file it is written in, and this one moved a directory down in the split.
  require_relative "../console_strip"
  started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  raw = "#{path}.cs_in.raw"
  cooked = "#{path}.cs_out.raw"
  ext = File.extname(path)
  out = "#{path}.console#{ext.empty? ? '.wav' : ext}"
  args = ext.downcase == ".wav" || ext.empty? ? ["-c:a", "pcm_s16le"] : codec_for(out)
  begin
    sh! "ffmpeg", "-y", "-i", path, "-f", "s16le", "-acodec", "pcm_s16le",
        "-ar", SAMPLE_RATE.to_s, "-ac", "2", raw
    inter = File.binread(raw).unpack("s<*")
    left = []
    right = []
    inter.each_slice(2) do |l, r|
      left << (l || 0) / PCM16_FULL_SCALE
      right << (r || l || 0) / PCM16_FULL_SCALE
    end
    left = ConsoleStrip.process(left, rate: SAMPLE_RATE, seed:, amount:)
    right = ConsoleStrip.process(right, rate: SAMPLE_RATE, seed: seed + 1, amount:)
    # Match the input peak rather than normalising to full scale. This stage
    # runs on a bus that is about to be mixed at a measured weight, and a
    # stage that silently changes its own level makes every downstream mix
    # number wrong -- which is how the low end got away from this engine
    # before.
    in_peak = inter.map(&:abs).max.to_f / PCM16_FULL_SCALE
    out_peak = [left.map(&:abs).max || 0.0, right.map(&:abs).max || 0.0].max
    scale = out_peak.positive? && in_peak.positive? ? in_peak / out_peak : 1.0
    merged = Array.new(left.length * 2)
    left.each_index do |i|
      merged[i * 2] = ((left[i] * scale) * 32_767).round.clamp(-32_768, 32_767)
      merged[(i * 2) + 1] = ((right[i] * scale) * 32_767).round.clamp(-32_768, 32_767)
    end
    File.binwrite(cooked, merged.pack("s<*"))
    # Same DC problem as the tape stage, an order of magnitude smaller but real:
    # ConsoleStrip.process turns a DC-free input into one offset by 1.31% of
    # peak at 0.35, 3.84% at 1.0. Any asymmetric
    # saturation does this, and both models run after the master chain's
    # highpasses, so nothing downstream was removing it.
    sh! "ffmpeg", "-y", "-f", "s16le", "-ar", SAMPLE_RATE.to_s, "-ac", "2",
        "-i", cooked, "-af", "highpass=f=24", "-ar", SAMPLE_RATE.to_s, "-ac", "2", *args, out
    FileUtils.mv(out, path)
    took = (Process.clock_gettime(Process::CLOCK_MONOTONIC) - started).round(1)
    dmesg("console strip: seed #{seed}/#{seed + 1} amount #{amount} (#{took}s)",
          unit: "cons0", parent: "dilla0")
    path
  rescue StandardError => e
    warn "console strip: #{e.message}"
    FileUtils.rm_f(out)
    path
  ensure
    FileUtils.rm_f([raw, cooked])
  end
end

def tape_hysteresis!(path)
  return path unless (TAPE_HYSTERESIS.positive? || TAPE_WOW_MS.positive?) && File.file?(path)

  require_relative "../tape_hysteresis"
  started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  raw = "#{path}.pre.raw"
  cooked = "#{path}.post.raw"
  ext = File.extname(path)
  out = "#{path}.tape#{ext.empty? ? '.wav' : ext}"
  args = ext.downcase == ".wav" || ext.empty? ? ["-c:a", "pcm_s16le"] : codec_for(out)
  begin
    decode = ["ffmpeg", "-y", "-i", path]
    decode += ["-af", "lowpass=f=#{TAPE_LOSS_HZ.round}"] if TAPE_LOSS_HZ.positive?
    decode += ["-f", "s16le", "-acodec", "pcm_s16le", "-ar", SAMPLE_RATE.to_s, "-ac", "1", raw]
    sh!(*decode)
    pcm = File.binread(raw).unpack("s<*").map { |s| s / PCM16_FULL_SCALE }
    if TAPE_HYSTERESIS.positive?
      pcm = TapeHysteresis.process(pcm, drive: 1.0 + (3.0 * TAPE_HYSTERESIS),
                                   params: TapeHysteresis.params_for_bias(TAPE_BIAS))
    end
    pcm = TapeHysteresis.apply_wow(pcm, rate: SAMPLE_RATE, depth_ms: TAPE_WOW_MS) if TAPE_WOW_MS.positive?
    peak = pcm.map(&:abs).max
    pcm = pcm.map { |v| v / peak * 0.94 } if peak&.positive?
    File.binwrite(cooked, pcm.map { |v| (v * 32_767).round.clamp(-32_768, 32_767) }.pack("s<*"))
    # Mono through the model, then re-widened against the original: running two
    # channels doubles a cost that is already the slowest thing here, and tape
    # magnetisation is not a stereo phenomenon anyway.
    sh! "ffmpeg", "-y", "-f", "s16le", "-ar", SAMPLE_RATE.to_s, "-ac", "1", "-i", cooked,
        "-i", path, "-filter_complex",
        # highpass=24 is load-bearing, not tidying. Jiles-Atherton models
        # remanent magnetisation, and remanence is a DC phenomenon: a DC-free
        # input comes out of TapeHysteresis.process with DC at 10.3% of peak at
        # drive 1.75, rising to 15.7% at 4.0. This stage runs
        # after every highpass in the master chain and then peak-normalises,
        # which preserves the offset instead of removing it.
        #
        # Unfixed, that offset dominated: 22 of 84 demo tracks measured DC up to
        # -0.62, and the worst was 99.7% subsonic — full-band RMS -4.10 dB
        # against -4.09 dB below 25 Hz, with the actual music 37 dB underneath
        # it and the headroom entirely consumed.
        "[0:a]aformat=channel_layouts=stereo,highpass=f=24[t];" \
        "[1:a]highpass=f=8000[air];" \
        "[t][air]amix=inputs=2:weights=1 0.35:duration=first:normalize=0[out]",
        "-map", "[out]", "-ar", SAMPLE_RATE.to_s, "-ac", "2", *args, out
    FileUtils.mv(out, path)
    took = (Process.clock_gettime(Process::CLOCK_MONOTONIC) - started).round(1)
    extras = []
    extras << "bias #{TAPE_BIAS}" if TAPE_BIAS < 1.0
    extras << "loss #{TAPE_LOSS_HZ.round}Hz" if TAPE_LOSS_HZ.positive?
    extras << "O-U wow #{TAPE_WOW_MS}ms" if TAPE_WOW_MS.positive?
    puts "tape: Jiles-Atherton hysteresis#{extras.empty? ? '' : " (#{extras.join(', ')})"} (#{took}s)"
    path
  rescue StandardError => e
    warn "tape hysteresis: #{e.message}"
    FileUtils.rm_f(out)
    path
  ensure
    FileUtils.rm_f([raw, cooked])
  end
end

# Tilt: lows up as highs come down, pivoting around a midpoint.
#
# The reason to tilt rather than shelve the top off. A plain high-shelf cut
# makes a mix darker AND smaller, because nothing replaces the energy removed --
# the perceived weight goes with the brightness. A tilt pivots: the bottom rises
# by the same amount the top falls, so the mix reads as relaxed rather than
# merely dull, and the loudness barely moves.
#
# Two shelves around a pivot rather than one filter, because that is what a tilt
# is. Pivot at 700 Hz: low enough that it does not thin the body, high enough
# that the lift lands on weight rather than on mud.
MASTER_TILT_DB = (ENV["MASTER_TILT_DB"] || 0).to_f.clamp(-6.0, 6.0)
MASTER_TILT_PIVOT = (ENV["MASTER_TILT_PIVOT"] || 700).to_i

# Top-end smoothing -- the thing that makes a mix read as calm rather than
# distorted, and the most consistent single trait across the 29 reference
# tracks in MASTER/reports/radio_bergen_track_dossiers.yml.
#
# Nine of those dossiers describe the same move in different words: "master
# lowpass ~3.6 kHz" (Camel, Massage Situation), "high shelf rolled ~9 kHz"
# (In Space), "limited highs" (Eye), "never harsh top" (Timeless), "Donuts
# lowpass warmth", and bergen_local's "master LP 2.7-3.1 kHz". Nothing in this
# engine implemented it; the only top-end control was VINYL.
#
# Those numbers are NOT taken literally. A brickwall lowpass at 3.2 kHz makes
# a record sound like a telephone -- real Donuts and Camel masters have
# cymbals well above 10 kHz -- so the figure is describing the treatment of
# the sampled bed, or the perceived centre of the rolloff, not a filter on the
# whole master. Implemented literally it would destroy the track, which is why
# this is a pair of gentle shelves instead.
#
# Two bands, because "harsh" and "bright" are different problems:
#
#   PRESENCE (~3.2 kHz) is where distortion and harshness actually live. This
#   is the band that makes saturation read as fizz rather than warmth, and it
#   is what the ear calls "distorted" even when nothing is clipping.
#
#   AIR (~9 kHz and up) is brightness. Rolling this alone makes a mix duller
#   without making it calmer, which is why cutting only here never fixes the
#   complaint.
# 2 dB out of the presence band by default. This is the stage that answers
# "harsh" directly, and it was doing nothing.
MASTER_SMOOTH_DB = (ENV["MASTER_SMOOTH_DB"] || 2.0).to_f.clamp(0.0, 12.0)
MASTER_SMOOTH_HZ = (ENV["MASTER_SMOOTH_HZ"] || 3200).to_i
MASTER_AIR_DB = (ENV["MASTER_AIR_DB"] || 0).to_f.clamp(0.0, 12.0)
MASTER_AIR_HZ = (ENV["MASTER_AIR_HZ"] || 9000).to_i

def master_smooth!(path)
  return path unless (MASTER_SMOOTH_DB.positive? || MASTER_AIR_DB.positive?) && File.file?(path)

  ext = File.extname(path)
  out = "#{path}.smooth#{ext.empty? ? '.wav' : ext}"
  args = ext.downcase == ".wav" || ext.empty? ? ["-c:a", "pcm_s16le"] : codec_for(out)
  chain = []
  # A wide bell on the presence band rather than a shelf: a shelf pulls
  # everything above the corner down together, taking the cymbals and the
  # sample's air with it. The harshness is a band, so it gets a band. Width in
  # octaves, wide enough not to sound like a notch.
  if MASTER_SMOOTH_DB.positive?
    chain << "equalizer=f=#{MASTER_SMOOTH_HZ}:t=o:w=1.6:g=#{-MASTER_SMOOTH_DB.round(2)}"
  end
  # Air gets a real shelf, because above 9 kHz there is nothing to preserve
  # the far side of. `treble` and not `equalizer` -- equalizer is a peaking
  # filter in every configuration, a mistake already made once in this file.
  chain << "treble=f=#{MASTER_AIR_HZ}:g=#{-MASTER_AIR_DB.round(2)}:width_type=q:w=0.7" if MASTER_AIR_DB.positive?
  return path if chain.empty?

  begin
    sh! "ffmpeg", "-y", "-i", path, "-af", chain.join(","),
        "-ar", SAMPLE_RATE.to_s, "-ac", "2", *args, out
    FileUtils.mv(out, path)
    dmesg("smooth: presence -#{MASTER_SMOOTH_DB} dB @ #{MASTER_SMOOTH_HZ}, " \
          "air -#{MASTER_AIR_DB} dB @ #{MASTER_AIR_HZ}",
          unit: "smth0", parent: "dilla0")
    path
  rescue StandardError => e
    warn "master smooth: #{e.message}"
    FileUtils.rm_f(out)
    path
  end
end

def master_tilt!(path)
  return path unless MASTER_TILT_DB.abs > 0.01 && File.file?(path)

  ext = File.extname(path)
  out = "#{path}.tilt#{ext.empty? ? '.wav' : ext}"
  args = ext.downcase == ".wav" || ext.empty? ? ["-c:a", "pcm_s16le"] : codec_for(out)
  # Negated so the sign reads the way a tilt control does: a NEGATIVE value
  # tilts down, meaning darker -- lows up, highs down. Unnegated, -3 brightened
  # (low -0.8 dB, high +0.9 dB), which is the opposite of what asking for -3
  # implies and the opposite of the chill it exists to produce.
  half = (-MASTER_TILT_DB / 2.0).round(3)
  begin
    sh! "ffmpeg", "-y", "-i", path,
        # `bass` and `treble`, not `equalizer`. equalizer is a PEAKING filter in
        # every case -- its `t` parameter selects the unit of the width (h=Hz,
        # q=Q, o=octaves), not the filter shape. Writing t=h intending "high
        # shelf" builds a bell 0.7 Hz wide instead, which measured as doing
        # nothing at all: low and high bands both moved 0.1 dB. Same class of
        # mistake as reaching for asoftclip to saturate.
        "-af", "bass=f=#{MASTER_TILT_PIVOT / 4}:g=#{half}:width_type=q:w=0.7," \
               "treble=f=#{MASTER_TILT_PIVOT * 6}:g=#{-half}:width_type=q:w=0.7",
        "-ar", SAMPLE_RATE.to_s, "-ac", "2", *args, out
    FileUtils.mv(out, path)
    dmesg("master tilt: #{half > 0 ? '+' : ''}#{half} low / #{-half} high around #{MASTER_TILT_PIVOT}Hz",
          unit: "mix0", parent: "dilla0")
    path
  rescue StandardError => e
    warn "master tilt: #{e.message}"
    FileUtils.rm_f(out)
    path
  end
end

# Collapse everything below MONO_BASS_HZ to mono, leave the rest alone.
#
# Two sources here put uncorrelated energy in the sub: the sampled record has
# whatever stereo width the original mastering gave it, and the pad stack is
# deliberately spread. Uncorrelated lows do not add up -- they smear, they
# partially cancel on any mono playback, and they eat headroom the kick needs.
# Summing only the bottom keeps the width where width is audible (a listener
# cannot localise 60 Hz anyway) and gives the low end back its definition.
MONO_BASS_HZ = (ENV["MONO_BASS_HZ"] || 0).to_i

def mono_bass!(path)
  return path unless MONO_BASS_HZ.positive? && File.file?(path)

  ext = File.extname(path)
  out = "#{path}.monobass#{ext.empty? ? '.wav' : ext}"
  args = ext.downcase == ".wav" || ext.empty? ? ["-c:a", "pcm_s16le"] : codec_for(out)
  chain = [
    "[0:a]asplit=2[mb_lo][mb_hi]",
    "[mb_lo]lowpass=f=#{MONO_BASS_HZ}," \
      "pan=stereo|c0=0.5*c0+0.5*c1|c1=0.5*c0+0.5*c1[mb_m]",
    "[mb_hi]highpass=f=#{MONO_BASS_HZ}[mb_s]",
    "[mb_m][mb_s]amix=inputs=2:normalize=0[mbout]",
  ]
  begin
    sh! "ffmpeg", "-y", "-i", path, "-filter_complex", chain.join(";"),
        "-map", "[mbout]", "-ar", SAMPLE_RATE.to_s, "-ac", "2", *args, out
    FileUtils.mv(out, path)
    path
  rescue StandardError => e
    warn "mono bass: #{e.message}"
    FileUtils.rm_f(out)
    path
  end
end

# --- drone bed and tape stop --------------------------------------------------
#
# The two effects the engine had no form of. It already owns bitcrush
# (acrusher), wow/flutter (vibrato), pitch tricks (asetrate), granular pads,
# detune, reverse grains and drum dropouts -- so those are switches, not work.
# A stretched drone and a speed brake were genuinely absent.

# Stretches a short slice of the loop into a static harmonic bed. Not real
# paulstretch (no phase randomisation -- ffmpeg has no such filter), but the
# audible part of it: overlapping windows so far apart that pitch survives and
# rhythm does not. Layering three ratios stops the result sounding like one
# obviously slowed sample.
DILLA_DRONE = ENV["DILLA_DRONE"] == "1"
DILLA_DRONE_VOL = (ENV["DILLA_DRONE_VOL"] || 0.16).to_f.clamp(0.0, 1.0)
DILLA_DRONE_SRC_SEC = (ENV["DILLA_DRONE_SRC_SEC"] || 0.6).to_f.clamp(0.1, 4.0)

# atempo floors at 0.5 per stage, so a deep stretch is a chain of them. Six
# stages of 0.5 is 64x. The last stage differs per layer so the three do not sit
# exactly on top of each other: identical copies sum to one louder copy, while
# slightly different ones beat, and the beating is what stops a drone sounding
# frozen.
DRONE_LAYER_TEMPOS = [
  [0.5, 0.5, 0.5, 0.5, 0.5, 0.5],
  [0.5, 0.5, 0.5, 0.5, 0.5, 0.55],
  [0.5, 0.5, 0.5, 0.5, 0.5, 0.62],
].freeze
DRONE_LOWPASS_HZ = 1800
DRONE_HIGHPASS_HZ = 70
DRONE_FADE_FRACTION = 0.25
DRONE_FADE_MAX_SEC = 6.0

def dilla_render_drone!(src, dest, duration:)
  return nil unless src && File.file?(src)

  chain = DRONE_LAYER_TEMPOS.each_with_index.map do |stages, i|
    tempo = stages.map { |s| "atempo=#{s}" }.join(",")
    "[0:a]#{tempo},lowpass=f=#{DRONE_LOWPASS_HZ},highpass=f=#{DRONE_HIGHPASS_HZ}," \
      "volume=#{(1.0 / DRONE_LAYER_TEMPOS.size).round(3)}[d#{i}]"
  end
  mix = DRONE_LAYER_TEMPOS.each_index.map { |i| "[d#{i}]" }.join
  chain << "#{mix}amix=inputs=#{DRONE_LAYER_TEMPOS.size}:normalize=0[dm]"
  # A drone that arrives and leaves is a bed; one that just starts is a mistake.
  fade = [duration * DRONE_FADE_FRACTION, DRONE_FADE_MAX_SEC].min.round(2)
  chain << "[dm]afade=t=in:st=0:d=#{fade}," \
           "afade=t=out:st=#{(duration - fade).round(2)}:d=#{fade}[dout]"
  begin
    sh! "ffmpeg", "-y", "-t", DILLA_DRONE_SRC_SEC.to_s, "-i", src,
        "-filter_complex", chain.join(";"), "-map", "[dout]",
        "-t", duration.round(3).to_s, "-ar", SAMPLE_RATE.to_s, "-ac", "2",
        "-c:a", "pcm_s16le", dest
    dest
  rescue StandardError => e
    warn "drone: #{e.message}"
    nil
  end
end

# Turntable brake over the final bars. asetrate resamples, so pitch and speed
# fall together the way a real platter does -- which is the point, and why this
# is not just a fade.
DILLA_TAPE_STOP = ENV["DILLA_TAPE_STOP"] == "1"
DILLA_TAPE_STOP_BEATS = (ENV["DILLA_TAPE_STOP_BEATS"] || 4).to_f.clamp(0.5, 32.0)

# ffmpeg cannot sweep asetrate continuously, so the brake is short slices at
# falling rates. 14 is enough that the steps read as a slide, not a staircase.
TAPE_STOP_STEPS = 14
# Where the platter ends up, as a fraction of speed. Not 0: the last slice would
# be stretched to nothing audible and simply pad the file with rumble.
TAPE_STOP_FINAL_RATE = 0.08
# >1 makes the fall accelerate, which is how a platter with real inertia stops.
TAPE_STOP_CURVE = 1.6
TAPE_STOP_MIN_RATE_HZ = 3000

def dilla_tape_stop_rates
  (0...TAPE_STOP_STEPS).map do |i|
    frac = 1.0 - ((i + 1).to_f / TAPE_STOP_STEPS)
    rest = 1.0 - TAPE_STOP_FINAL_RATE
    [TAPE_STOP_FINAL_RATE + (rest * (frac**TAPE_STOP_CURVE)),
     TAPE_STOP_MIN_RATE_HZ.to_f / SAMPLE_RATE].max
  end
end

def dilla_tape_stop!(path, beat_bpm:)
  total = audio_duration_sec(path).to_f
  want = (60.0 / beat_bpm) * DILLA_TAPE_STOP_BEATS
  steps = TAPE_STOP_STEPS
  # Slowed audio lasts longer, so the source window has to be SHORTER than the
  # brake we want to hear. Taking the requested length as the source instead
  # made "4 beats" produce 8.9 seconds -- a fifth of a 16-bar track. Solve for
  # the source window whose stretched total lands on the request.
  rates = dilla_tape_stop_rates
  stretch = rates.sum { |r| 1.0 / r } / steps
  brake = want / stretch
  return path unless total > brake + 1.0

  head = "#{path}.head.wav"
  tailp = "#{path}.tail.wav"
  out = "#{path}.stopped.wav"
  begin
    sh! "ffmpeg", "-y", "-i", path, "-t", (total - brake).round(3).to_s,
        "-c:a", "pcm_s16le", head
    # Ramped resample in steps: ffmpeg cannot sweep asetrate continuously, so
    # the brake is built from short slices at falling rates. 14 is enough that
    # the steps read as a slide rather than a staircase.
    slice = brake / steps
    parts = (0...steps).map do |i|
      rate = (SAMPLE_RATE * rates[i]).round
      seg = "#{path}.b#{i}.wav"
      sh! "ffmpeg", "-y", "-ss", (total - brake + (i * slice)).round(3).to_s,
          "-t", slice.round(3).to_s, "-i", path,
          "-af", "asetrate=#{rate},aresample=#{SAMPLE_RATE}",
          "-ar", SAMPLE_RATE.to_s, "-ac", "2", "-c:a", "pcm_s16le", seg
      seg
    end
    # Absolute paths: the concat demuxer resolves relative entries against the
    # LIST FILE's directory, not the process working directory. With a relative
    # destination like renders/demos/x.wav the list sat in renders/demos/ and
    # its entries resolved to renders/demos/renders/demos/... -- so the brake
    # failed on every relative path and silently returned the unbraked file.
    # It only ever worked because the first renders wrote to absolute paths.
    list = "#{path}.list.txt"
    File.write(list, ([head] + parts).map { |f| "file '#{File.expand_path(f)}'\n" }.join)
    sh! "ffmpeg", "-y", "-f", "concat", "-safe", "0", "-i", list,
        "-ar", SAMPLE_RATE.to_s, "-ac", "2", "-c:a", "pcm_s16le", out
    FileUtils.mv(out, path)
    # Recorded before the slices are deleted on the next line: the parts of a
    # tape brake exist only inside this method, so this is the only moment their
    # durations and hashes can be read at all.
    DillaProvenance.record_assembly!(path, parts: [head] + parts,
                                           how: "tape stop: head plus #{parts.length} decelerating slice(s)")
    FileUtils.rm_f([head, tailp, list] + parts)
    path
  rescue StandardError => e
    warn "tape stop: #{e.message}"
    # `parts` too. Omitting them left 14 slices beside every failed brake, and
    # since the failure was silent the leftovers were the only visible sign
    # anything had gone wrong at all.
    FileUtils.rm_f([head, tailp, out, "#{path}.list.txt"] + Array(parts))
    path
  end
end
