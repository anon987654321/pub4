# frozen_string_literal: true

# Which regions of a record are worth sampling.
#
# chop ranks candidates by self-similarity and rejoin cost, which finds SEAMLESS
# regions. It has never asked whether a region is BEAUTIFUL, and those are
# different questions -- a seamless loop of a boring bar is still boring. This is
# the second question, asked in seven measured terms.
#
# One decode, one contour per source, arithmetic over stored scalars for every
# window after that. Overlapping candidates never re-measure the same second.
#
# No ffmpeg filter graph on purpose. aspectralstats repeats stale rows after
# asetnsamples, Crest_factor is silently absent from astats Overall, and
# acrossover leaks across its own slope -- three separate instrument traps, none
# of which exist in a raw decode plus Ruby.
module DillaSampleWorth
  RATE = 11_025          # Nyquist 5512Hz; everything above it folds into the
  LOWPASS = 5000         # body band, so the decode is band-limited first.
  FFT_N = 4096           # 2.69Hz bins: a semitone at C2 is 3.9Hz wide.
  HOP_SEC = 0.25
  CELLS = 60             # C2..B6, one per semitone
  C2 = 65.406
  FLOOR_BLOCK_SEC = 120  # a 39-minute broadcast is many records, and one
                         # record's noise bed is the wrong denominator for
                         # another's.

  # Krumhansl-Schmuckler profiles. Imported rather than re-derived: dilla.rb
  # already carries these and a second copy would drift.
  MAJOR = [6.35, 2.23, 3.48, 2.33, 4.38, 4.09, 2.52, 5.19, 2.39, 3.66, 2.29, 2.88].freeze
  MINOR = [6.33, 2.68, 3.52, 5.38, 2.60, 3.53, 2.54, 4.75, 3.98, 2.69, 3.34, 3.17].freeze

  HARMONIC_OFFSETS = [0, 12, 19, 24, 28].freeze # 1st..5th partial, in semitones
  HARMONIC_WEIGHTS = [1.0, 0.5, 0.33, 0.25, 0.2].freeze

  WEIGHTS = { tonal: 0.22, thin: 0.20, body: 0.17, pitched: 0.14,
              smooth: 0.10, hold: 0.09, poly: 0.08 }.freeze
  HARMONY_TERMS = %i[tonal pitched smooth poly].freeze
  # When the middle half of a record's windows spans less than this in Krumhansl
  # fit, the harmony group is not ranking, it is ranking noise.
  CONF_SPREAD = 0.08
  HARMONY_FLAT = 0.27 # what harmony contributes when it is not trusted

  module_function

  def contour(path, rate: RATE)
    pcm = decode(path, rate)
    return nil if pcm.length < FFT_N * 2

    frames = spectral_frames(pcm, rate)
    subtract_floor!(frames, rate)
    frames.each { |f| f[:tonal] = krumhansl(f[:chroma]) }
    { path: path, rate: rate, frames: frames, kenv: kick_envelope(pcm, rate),
      duration: pcm.length.to_f / rate }
  end

  # Raw terms for one window. Ranking happens across windows, not here: every
  # term is a percentile among the windows scored on the same source, which is
  # what makes a weight of 0.22 impossible to outvote by a term with a wider
  # native range.
  def terms(contour, from:, dur:)
    fs = frames_in(contour, from, dur)
    return nil if fs.empty?

    { tonal: mean(fs.map { |f| f[:tonal] }),
      pitched: mean(fs.map { |f| f[:expl] }),
      smooth: -mean(fs.map { |f| f[:rough] }),
      poly: -(mean(fs.map { |f| f[:nnotes] }) - 5.5).abs,
      body: mean(fs.map { |f| f[:body_share] }),
      hold: -stddev(fs.map { |f| f[:body_db] }),
      thin: thinness(contour, from, dur) }
  end

  # rows: [{terms:, gates:}, ...] for every window on one source.
  def score_all(rows, conf:)
    return [] if rows.empty?

    columns = WEIGHTS.keys.to_h { |t| [t, rows.map { |r| r[:terms][t] }.sort] }
    rows.map do |row|
      ranked = WEIGHTS.keys.to_h { |t| [t, percentile(columns[t], row[:terms][t])] }
      harm = HARMONY_TERMS.sum { |t| WEIGHTS[t] * ranked[t] }
      tex = (WEIGHTS.keys - HARMONY_TERMS).sum { |t| WEIGHTS[t] * ranked[t] }
      gate = (row[:gates] || {}).values.inject(1.0, :*)
      sw = ((conf * harm) + ((1.0 - conf) * HARMONY_FLAT) + tex) * gate
      { sw: sw.round(4), ranked: ranked, raw: row[:terms], conf: conf.round(3) }
    end
  end

  # A per-source constant, not a per-window term. As a per-window multiplier it
  # becomes the strongest single driver of the ordering and the scorer silently
  # ranks by "most obviously tonal", which promotes solo piano over the dense
  # modal jazz this crate is full of.
  def confidence(tonals)
    return 0.0 if tonals.size < 4

    sorted = tonals.sort
    spread = quantile(sorted, 0.75) - quantile(sorted, 0.25)
    clamp(spread / CONF_SPREAD, 0.0, 1.0)
  end

  def gates(contour, from:, dur:, vocals_db: nil)
    fs = frames_in(contour, from, dur)
    return { silent: 0.0 } if fs.empty?

    all_rms = contour[:frames].map { |f| f[:rms_db] }
    median_rms = quantile(all_rms.sort, 0.5)
    g = {}
    g[:silent] = mean(fs.map { |f| f[:rms_db] }) < median_rms - 20 ? 0.0 : 1.0
    g[:fade] = fade_slope(fs).abs > 8.0 ? 0.4 : 1.0
    # Reads the number chop already computes and writes to the registry. A fresh
    # volumedetect pass would be a second source for one fact.
    g[:vocal] = vocals_db ? 0.35 + (0.65 * clamp((-6.0 - vocals_db) / 19.0, 0.0, 1.0)) : 1.0
    g
  end

  # --- the instrument ------------------------------------------------------

  def decode(path, rate)
    cmd = ["ffmpeg", "-v", "error", "-i", path, "-af", "lowpass=f=#{LOWPASS}",
           "-ac", "1", "-ar", rate.to_s, "-f", "s16le", "-"]
    raw = IO.popen(cmd, "rb", err: File::NULL, &:read).to_s
    raw.unpack("s<*").map { |s| s / 32_768.0 }
  end

  def spectral_frames(pcm, rate)
    hop = (HOP_SEC * rate).round
    window = hann(FFT_N)
    frames = []
    pos = 0
    while pos + FFT_N <= pcm.length
      power = fft_power(pcm[pos, FFT_N].each_with_index.map { |v, i| v * window[i] })
      frames << frame_features(power, rate, pos.to_f / rate)
      pos += hop
    end
    frames
  end

  def frame_features(power, rate, at)
    bin_hz = rate.to_f / FFT_N
    cells = Array.new(CELLS, 0.0)
    CELLS.times do |c|
      centre = C2 * (2.0**(c / 12.0))
      lo = (centre / (2.0**(1 / 24.0)) / bin_hz).ceil
      hi = (centre * (2.0**(1 / 24.0)) / bin_hz).floor
      (lo..hi).each { |k| cells[c] += power[k] if k >= 0 && k < power.length }
    end
    { at: at, cells: cells,
      p_kick: band(power, bin_hz, 40, 220),
      p_body: band(power, bin_hz, 300, 2000),
      p_tot: band(power, bin_hz, 40, 5000) }
  end

  # Per-source hiss floor, per block. Without it a loop reads one value alone
  # and another inside a concatenation of unrelated cuts.
  def subtract_floor!(frames, rate)
    block = (FLOOR_BLOCK_SEC / HOP_SEC).round
    frames.each_slice(block) do |slice|
      CELLS.times do |c|
        floor = quantile(slice.map { |f| f[:cells][c] }.sort, 0.10)
        slice.each { |f| f[:cells][c] = [f[:cells][c] - floor, 0.0].max }
      end
    end
    frames.each { |f| finish_frame!(f) }
  end

  def finish_frame!(f)
    peak = f[:cells].max
    f[:cells] = peak.positive? ? f[:cells].map { |v| v / peak } : f[:cells]
    f[:chroma] = chroma(f[:cells])
    picks, expl = harmonic_picks(f[:cells])
    f[:nnotes] = picks.length
    f[:expl] = expl
    f[:rough] = roughness(f[:cells])
    f[:body_share] = f[:p_tot].positive? ? f[:p_body] / f[:p_tot] : 0.0
    f[:rms_db] = 10 * Math.log10(f[:p_tot] + 1e-12)
    f[:body_db] = 10 * Math.log10(f[:p_body] + 1e-12)
    f.delete(:cells)
  end

  def chroma(cells)
    c12 = Array.new(12, 0.0)
    cells.each_with_index { |v, i| c12[i % 12] += v }
    peak = c12.max
    peak.positive? ? c12.map { |v| v / peak } : c12
  end

  # Only the magnitude is used. Two competent Krumhansl implementations over the
  # same audio agree on the root about half the time, so any term that depends
  # on knowing the root inherits that -- and none is in this scorer.
  def krumhansl(c12)
    (0...12).flat_map do |rot|
      rotated = c12.rotate(rot)
      [correlate(rotated, MAJOR), correlate(rotated, MINOR)]
    end.max
  end

  def harmonic_picks(cells)
    res = cells.dup
    picks = []
    first = nil
    8.times do
      sal = (0...CELLS).map do |c|
        HARMONIC_OFFSETS.each_with_index.sum do |o, i|
          c + o < CELLS ? HARMONIC_WEIGHTS[i] * res[c + o] : 0.0
        end
      end
      best = sal.each_with_index.max_by(&:first)
      break unless best

      s, c = best
      first ||= s
      break if s <= 0 || s < 0.35 * first

      picks << c
      amp = res[c]
      HARMONIC_OFFSETS.each_with_index do |o, i|
        res[c + o] = [res[c + o] - (HARMONIC_WEIGHTS[i] * amp), 0.0].max if c + o < CELLS
      end
    end
    total = cells.sum
    explained = picks.flat_map { |c| HARMONIC_OFFSETS.map { |o| c + o } }
                     .uniq.select { |c| c < CELLS }.sum { |c| cells[c] }
    [picks, total.positive? ? explained / total : 0.0]
  end

  # Plomp-Levelt below 988Hz. The skirt test is load-bearing: without it
  # spectral leakage makes a single sine the roughest signal measurable, and the
  # naive fix in the other direction merges two notes a semitone apart and calls
  # them perfectly smooth. Restricted to the low register because measured full
  # band the term calls a bare major triad maximally rough, which is correct
  # physics and the wrong sign for the question being asked.
  def roughness(cells)
    peak = cells.max
    return 0.0 unless peak.positive?

    partials = (0..47).select do |c|
      next false if cells[c] < 0.12 * peak

      [c - 1, c + 1].none? do |n|
        n >= 0 && n < CELLS && cells[n] > cells[c] && cells[c] < 0.35 * cells[n]
      end
    end
    return 0.0 if partials.size < 2

    num = 0.0
    den = 0.0
    partials.combination(2) do |i, j|
      fi = C2 * (2.0**(i / 12.0))
      fj = C2 * (2.0**(j / 12.0))
      ai = Math.sqrt(cells[i])
      aj = Math.sqrt(cells[j])
      s = 0.24 / ((0.0207 * fi) + 18.96)
      d = fj - fi
      num += ai * aj * (Math.exp(-3.5 * s * d) - Math.exp(-5.75 * s * d))
      den += ai * aj
    end
    den.positive? ? num / den : 0.0
  end

  # The only term that asks about the record rather than about the window: how
  # much thinner is the arrangement here than this record's own habit.
  def kick_envelope(pcm, rate)
    a_lo = 1 - Math.exp(-2 * Math::PI * 220 / rate.to_f)
    a_hi = 1 - Math.exp(-2 * Math::PI * 40 / rate.to_f)
    y_lo = 0.0
    y_hi = 0.0
    hop = (0.05 * rate).round
    env = []
    acc = 0.0
    count = 0
    pcm.each do |x|
      y_lo += a_lo * (x - y_lo)
      y_hi += a_hi * (x - y_hi)
      k = y_lo - y_hi
      acc += k * k
      count += 1
      next unless count == hop

      env << 20 * Math.log10(Math.sqrt(acc / hop) + 1e-9)
      acc = 0.0
      count = 0
    end
    env
  end

  def thinness(contour, from, dur)
    env = contour[:kenv]
    return 0.5 if env.length < 20

    median = quantile(env.sort, 0.5)
    rate = onset_rate(env, median, (from / 0.05).round, (dur / 0.05).round)
    blocks = (0...(env.length / 160)).map { |b| onset_rate(env, median, b * 160, 160) }
    base = blocks.empty? ? rate : quantile(blocks.sort, 0.5)
    return 0.5 unless base.positive?

    1.0 - clamp(rate / base, 0.0, 1.0)
  end

  # All three conditions required. Without the median guard the detector fires
  # on noise in an empty kick band -- thirty hits in the first thirty seconds of
  # a record whose kick band sat at -42dB.
  def onset_rate(env, median, start, len)
    return 0.0 if len <= 0

    hits = 0
    last = -99
    (start...[start + len, env.length].min).each do |j|
      next if j < 4

      prev = env[j - 4, 4]
      next unless prev && prev.length == 4
      next unless env[j] >= mean(prev) + 5.0 && env[j] > median - 8.0 && env[j] > -60.0
      next if j - last < 2

      hits += 1
      last = j
    end
    hits / (len * 0.05)
  end

  # --- arithmetic ----------------------------------------------------------

  def frames_in(contour, from, dur)
    contour[:frames].select { |f| f[:at] >= from && f[:at] < from + dur }
  end

  def fade_slope(fs)
    return 0.0 if fs.size < 3

    xs = fs.map { |f| f[:at] }
    ys = fs.map { |f| f[:rms_db] }
    mx = mean(xs)
    my = mean(ys)
    den = xs.sum { |x| (x - mx)**2 }
    return 0.0 unless den.positive?

    (xs.each_with_index.sum { |x, i| (x - mx) * (ys[i] - my) } / den) * 10.0
  end

  def percentile(sorted, value)
    return 0.5 if sorted.size < 4

    below = sorted.count { |v| v < value }
    ties = sorted.count { |v| v == value }
    (below + (0.5 * ties)) / (sorted.size - 1).to_f
  end

  def quantile(sorted, q)
    return 0.0 if sorted.empty?

    sorted[[(q * (sorted.size - 1)).round, sorted.size - 1].min]
  end

  def correlate(a, b)
    ma = mean(a)
    mb = mean(b)
    num = a.each_with_index.sum { |v, i| (v - ma) * (b[i] - mb) }
    den = Math.sqrt(a.sum { |v| (v - ma)**2 } * b.sum { |v| (v - mb)**2 })
    den.positive? ? num / den : 0.0
  end

  def band(power, bin_hz, lo, hi)
    ((lo / bin_hz).ceil..(hi / bin_hz).floor).sum { |k| k < power.length ? power[k] : 0.0 }
  end

  def hann(n) = (0...n).map { |i| 0.5 - (0.5 * Math.cos(2 * Math::PI * i / (n - 1))) }
  def mean(a) = a.empty? ? 0.0 : a.sum / a.size.to_f

  def stddev(a)
    return 0.0 if a.size < 2

    m = mean(a)
    Math.sqrt(a.sum { |v| (v - m)**2 } / (a.size - 1).to_f)
  end

  def clamp(v, lo, hi) = [[v, lo].max, hi].min

  # Iterative radix-2, precomputed twiddles. Power spectrum only, so the
  # imaginary half of the output is never needed by a caller.
  def fft_power(samples)
    n = samples.length
    re = samples.dup
    im = Array.new(n, 0.0)
    j = 0
    (0...n - 1).each do |i|
      if i < j
        re[i], re[j] = re[j], re[i]
        im[i], im[j] = im[j], im[i]
      end
      k = n >> 1
      while k <= j
        j -= k
        k >>= 1
      end
      j += k
    end
    size = 2
    while size <= n
      half = size / 2
      step = -2.0 * Math::PI / size
      (0...n).step(size) do |i|
        half.times do |k|
          ang = step * k
          wr = Math.cos(ang)
          wi = Math.sin(ang)
          a = i + k
          b = a + half
          tr = (wr * re[b]) - (wi * im[b])
          ti = (wr * im[b]) + (wi * re[b])
          re[b] = re[a] - tr
          im[b] = im[a] - ti
          re[a] += tr
          im[a] += ti
        end
      end
      size <<= 1
    end
    (0...n / 2).map { |k| (re[k] * re[k]) + (im[k] * im[k]) }
  end
end
