# frozen_string_literal: true

require "tmpdir"
#
# Measuring where the drums actually land.
#
# Part of the dilla engine, split out of dilla.rb. Defines methods and
# constants at top level exactly as it did there; dilla.rb requires the
# parts in the file's original order, because several constants are
# computed at load time from ones declared above them.
#
# dilla_quality already measures loudness, spectrum, phase and harmony, and
# compares a render against a baseline. What nothing measured is TIME -- and
# time is this engine's whole subject. A refactor, a reordered require or a
# changed default can move every hit ten milliseconds and leave the spectrum,
# the LUFS and the phase correlation identical, so the existing report would
# call it unchanged. That is the gap this closes.
#
# It is also the instrument the groove work needs. "The drums do not feel like
# the records" is not answerable by listening twice; it is answerable by
# measuring where the hits sit against the grid and comparing the shape of that
# distribution to what the analyses describe.
#
# The existing onset code cannot be reused for this. wonky_onsets_adaptive ends
# in flylo_quantize_onsets, which rounds every hit to the nearest sixteenth --
# it exists to LEARN a grid, so it deliberately throws away the deviation that
# is the entire measurement here. Its 50 ms analysis window could not resolve a
# 20 ms lean in any case.

# 2 ms. A hop has to be several times smaller than the thing it measures, and
# the leans in this engine's own tables run 8-28 ms.
POCKET_HOP_SEC = 0.002
POCKET_RATE = 22_050
# The frame is a whole number of samples, so the hop that actually happened is
# not the one that was asked for: 22050 * 0.002 truncates to 44 samples, and
# 44 / 22050 is 0.00199546 s. Multiplying frame indices by the NOMINAL 0.002
# runs the ruler 0.23% fast, which is 68 ms of accumulated error half a minute
# into a take -- it measured a fixture whose kick sits exactly on the grid as
# +35 ms late, and the lateness grew with time like a drummer speeding up.
# Every conversion below uses the real hop.
POCKET_FRAME_SAMPLES = (POCKET_RATE * POCKET_HOP_SEC).to_i
POCKET_ACTUAL_HOP_SEC = POCKET_FRAME_SAMPLES / POCKET_RATE.to_f

# One band per voice, chosen so a hit in one is not counted again in another.
# The snare band starts above the kick's body and stops below the hat's air.
POCKET_BANDS = {
  kick:  "highpass=f=35,lowpass=f=120",
  # Three highpass poles, not one. A single 180 Hz pole is 12 dB/oct and a kick
  # is loud enough to clear it: the snare band counted 72 hits on a fixture with
  # 24 snares and 48 kicks, which is every kick arriving a second time under
  # another name. Extra poles cost nothing and a snare's body sits above them.
  snare: "highpass=f=220,highpass=f=220,highpass=f=220,lowpass=f=1200",
  hat:   "highpass=f=6000"
}.freeze

# How far either side of a grid line a hit is still that hit. A sixteenth at 90
# BPM is 167 ms, so half of it is 83: past that the hit belongs to the next
# subdivision and calling it "late" would be an arithmetic accident.
POCKET_MAX_DEVIATION_RATIO = 0.5

# Every band filter delays what passes through it, and by a different amount.
#
# These are causal biquads, so a 35 Hz highpass pushes a kick tens of
# milliseconds later than a 6 kHz highpass pushes a hat. Measured on a fixture
# built with kick on the grid, snare 20 ms early and hat 25 ms late, the raw
# readings were +37.6, +30.0 and +28.6 -- three different biases that look
# exactly like a groove and are entirely the instrument.
#
# So calibrate: send one broadband burst at a known time through each band and
# see when it comes out. The delay belongs to the filter and the ffmpeg build,
# not to the music, which is why it is measured at run time rather than written
# down as a number that would rot the next time either changes.
POCKET_IMPULSE_AT_SEC = 0.5

def pocket_band_delay_frames
  @pocket_band_delay_frames ||= begin
    rate = 44_100
    tmp = File.join(Dir.tmpdir, "pocket_calib_#{Process.pid}.wav")
    pcm = Array.new(rate, 0)
    spike = (POCKET_IMPULSE_AT_SEC * rate).round
    # A 1 ms burst carrying one partial per band, so each band answers to its
    # own content rather than to a click that is all frequencies at once.
    (0...(0.001 * rate).round).each do |i|
      t = i / rate.to_f
      pcm[spike + i] = ((Math.sin(2 * Math::PI * 80 * t) +
                         Math.sin(2 * Math::PI * 600 * t) +
                         Math.sin(2 * Math::PI * 9000 * t)) / 3.0 * 30_000).round
    end
    body = pcm.pack("s<*")
    File.binwrite(tmp, "RIFF" + [36 + body.bytesize].pack("V") + "WAVE" + "fmt " +
                       [16].pack("V") + [1, 1].pack("v2") + [rate, rate * 2].pack("V2") +
                       [2, 16].pack("v2") + "data" + [body.bytesize].pack("V") + body)
    truth = (POCKET_IMPULSE_AT_SEC / POCKET_HOP_SEC).round
    out = POCKET_BANDS.to_h do |role, filter|
      onsets = pocket_onsets(pocket_envelope(tmp, filter), min_gap_frames: 10)
      [role, onsets.empty? ? 0 : (onsets.first - truth)]
    end
    File.delete(tmp) if File.exist?(tmp)
    out
  end
end

def pocket_envelope(path, filter)
  raw = IO.popen(["ffmpeg", "-v", "error", "-i", path, "-af", filter,
                  "-ac", "1", "-ar", POCKET_RATE.to_s, "-f", "s16le", "-"], "rb", &:read)
  samples = raw.to_s.unpack("s<*")
  return [] if samples.empty?

  frame = (POCKET_RATE * POCKET_HOP_SEC).to_i
  samples.each_slice(frame).map do |chunk|
    Math.sqrt(chunk.sum { |s| (s / 32_768.0)**2 } / chunk.size)
  end
end

# Where a hit STARTS, not where it is loudest.
#
# The first version of this picked local maxima of the RMS envelope, and it
# measured a fixture built with kick on the grid, snare 20 ms early and hat
# 25 ms late as +13, +30 and +31. Two faults, both of which a listening test
# would have hidden.
#
# An envelope peaks a few milliseconds AFTER the attack, because energy has to
# accumulate before the window is full -- so peak-picking reports every hit
# late by an amount that depends on the sound's own attack time. A kick and a
# hat get different biases, which is the worst case: it looks like groove.
#
# And a threshold on level alone re-detects the decay, so a 24-hit snare part
# came back as 109 hits.
#
# Rising-edge flux fixes both. The onset is the frame where energy increases
# fastest, which is the attack itself and is independent of how long the sound
# rings afterwards; a decaying tail has negative flux and cannot trigger.
def pocket_onsets(env, min_gap_frames:)
  return [] if env.length < 8

  flux = Array.new(env.length, 0.0)
  (1...env.length).each { |i| flux[i] = [env[i] - env[i - 1], 0.0].max }

  active = flux.reject(&:zero?).sort
  return [] if active.empty?

  # A percentile of the RISES, so a busy part and a sparse one are both
  # measured against their own transients rather than a fixed level.
  thresh = active[(active.length * 0.82).to_i]
  return [] unless thresh.positive?

  onsets = []
  i = 1
  while i < flux.length - 1
    if flux[i] >= thresh && flux[i] >= flux[i - 1] && flux[i] >= flux[i + 1]
      onsets << i
      i += min_gap_frames
    else
      i += 1
    end
  end
  onsets
end

# Signed milliseconds from the nearest sixteenth. Negative is early.
def pocket_deviations(onsets, bpm)
  step = (60.0 / bpm) / 4.0
  limit = step * POCKET_MAX_DEVIATION_RATIO
  onsets.filter_map do |frame|
    t = frame * POCKET_ACTUAL_HOP_SEC
    dev = t - ((t / step).round * step)
    next if dev.abs > limit
    (dev * 1000.0).round(2)
  end
end

def pocket_stats(devs)
  return { hits: 0 } if devs.empty?

  sorted = devs.sort
  mean = devs.sum / devs.length.to_f
  var = devs.sum { |d| (d - mean)**2 } / devs.length.to_f
  {
    hits: devs.length,
    mean_ms: mean.round(2),
    median_ms: sorted[sorted.length / 2].round(2),
    stddev_ms: Math.sqrt(var).round(2),
    early_pct: ((devs.count(&:negative?) / devs.length.to_f) * 100).round(1)
  }
end

# The whole measurement for one file.
# A transient is broadband whatever made it, so a kick's attack puts energy in
# the snare band and the hat band too. Steeper filters do not help -- the
# content is genuinely there. On a fixture with 48 kicks and 24 snares the
# snare band reported 72 hits, which is every kick counted a second time under
# another name.
#
# So an onset in a higher band that coincides with a kick is attributed to the
# kick. The cost is stated rather than hidden: a snare struck exactly with a
# kick is credited to the kick and drops out of the snare's distribution. That
# loses real hits, and it is still the right trade for a timing measurement --
# a phantom snare sitting at the kick's position drags the snare's mean toward
# the kick's, which reads as the backbeat having moved.
POCKET_COINCIDENCE_SEC = 0.012

def pocket_suppress_bleed(onsets, kick_onsets, hop)
  return onsets if kick_onsets.empty?

  window = (POCKET_COINCIDENCE_SEC / hop).round
  onsets.reject { |o| kick_onsets.any? { |k| (o - k).abs <= window } }
end

def pocket_timing_report(path, bpm:)
  raise ArgumentError, "bpm must be positive" unless bpm.to_f.positive?

  kick_frames = nil
  roles = POCKET_BANDS.to_h do |role, filter|
    # A hat can legitimately fall every 32nd; a kick cannot. Gapping them the
    # same either merges hat pairs or splits a kick's own decay into two hits.
    gap = role == :hat ? 0.030 : 0.060
    env = pocket_envelope(path, filter)
    onsets = pocket_onsets(env, min_gap_frames: (gap / POCKET_ACTUAL_HOP_SEC).round)
    # Take the filter's own delay off before anything is called early or late.
    lag = pocket_band_delay_frames[role].to_i
    aligned = onsets.map { |o| o - lag }
    if role == :kick
      kick_frames = aligned
    else
      aligned = pocket_suppress_bleed(aligned, kick_frames || [], POCKET_ACTUAL_HOP_SEC)
    end
    [role, pocket_stats(pocket_deviations(aligned, bpm.to_f))]
  end
  {
    schema: "dilla.timing.v1",
    path: File.expand_path(path),
    bpm: bpm.to_f,
    hop_ms: (POCKET_ACTUAL_HOP_SEC * 1000).round(4),
    roles: roles
  }
end

# Two reports side by side. A refactor that changed no timing shows every delta
# near zero; one that moved the pocket shows it in the mean, and one that made
# the playing less consistent shows it in the stddev even when the mean holds.
def pocket_timing_delta(current, baseline)
  POCKET_BANDS.keys.to_h do |role|
    now = current[:roles][role] || {}
    was = baseline.dig(:roles, role) || baseline.dig("roles", role.to_s) || {}
    [role, {
      mean_ms: ((now[:mean_ms] || 0) - (was[:mean_ms] || was["mean_ms"] || 0)).round(2),
      stddev_ms: ((now[:stddev_ms] || 0) - (was[:stddev_ms] || was["stddev_ms"] || 0)).round(2),
      hits: (now[:hits] || 0) - (was[:hits] || was["hits"] || 0)
    }]
  end
end
