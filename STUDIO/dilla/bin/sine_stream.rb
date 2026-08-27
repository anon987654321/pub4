# Every chord progression in the catalogue as sine tones, continuous.
#
# No engine, no pads, no drums -- just the harmony, so what is actually in the
# voicing is audible with nothing on top of it. Each chord is its upper voices
# plus its own bass_hz, which the harmony scorer carries separately and which
# nothing else here had been sounding.
#
# Progressions cross-fade into each other and several are rendered into one
# file, because afplay leaves a gap between files and a gap is the one thing
# this stream is not allowed to have.
Dir.chdir("/Users/mac/Documents/GitHub/pub4/STUDIO/dilla")
require "./dilla.rb"

RATE = 44_100
OUT = "/Users/mac/Music/dilla_sines"
PROGRESS = File.join(OUT, "now_playing.txt")
STOP = File.join(OUT, "STOP")
XFADE = (ENV["SINE_XFADE_SECS"] || "1.4").to_f
SECS = (ENV["SINE_CHORD_SECS"] || "3.2").to_f
# Down a semitone, because everything sits meaner a half-step below where it was
# written. Applied to every voice including the bass, so the whole field moves
# together rather than the tuning coming apart.
PITCH = 2.0**((ENV["SINE_PITCH_SEMITONES"] || "-1").to_f / 12.0)
PER_FILE = (ENV["SINE_PROGS_PER_FILE"] || "6").to_i

# Eight ways to voice the same sine. Rotated per progression so the stream keeps
# moving through textures instead of being one timbre for ninety minutes.
TREATMENTS = %i[plain shimmer halo tremolo drift sub bloom swell
                copymachine lpg plaits cloud fugue echo dub].freeze

# Detroit drums, synthesized rather than sampled, because this stream has no
# sampler in it and a kick that is a pitch-dropping sine IS a 909 kick.
#
# The timing is the point. Hats land LATE and kicks land EARLY against the
# same grid -- two clocks disagreeing, which is the whole Dilla-time idea and
# the one thing a quantized drum machine cannot do. The offsets below are in
# fractions of a sixteenth, not milliseconds, so they scale with the tempo.
HAT_LATE = 0.24
KICK_EARLY = -0.06
GHOST_LATE = 0.31

# tanh, hard: the drums are meant to be heavily processed, and tanh is the
# cheap honest saturator -- it rounds the peak instead of clipping it square.
def saturate(x, drive)
  Math.tanh(x * drive) / Math.tanh(drive)
end

def kick!(l, r, at, rate_secs)
  n = (RATE * 0.42).to_i
  start = at
  ph = 0.0
  n.times do |i|
    t = i.to_f / n
    # 118 Hz down to 41 Hz over the first fifth of the hit: the drop IS the kick.
    hz = 41.0 + 77.0 * Math.exp(-t * 22.0)
    ph += 2 * Math::PI * hz / RATE
    env = Math.exp(-t * 6.2)
    click = i < 90 ? (1.0 - i / 90.0) * 0.35 : 0.0
    s = saturate(Math.sin(ph) * env + click, 3.4) * 0.92 * env
    j = start + i
    break if j >= l.length
    l[j] += s
    r[j] += s
  end
end

def hat!(l, r, at, open, seed)
  n = (RATE * (open ? 0.20 : 0.055)).to_i
  rnd = Random.new(seed)
  hp = 0.0
  n.times do |i|
    t = i.to_f / n
    white = rnd.rand * 2.0 - 1.0
    # One-pole high pass, run twice: noise minus its own low end is a hat.
    hp = 0.86 * (hp + white)
    env = Math.exp(-t * (open ? 6.0 : 26.0))
    s = saturate(hp * env, 2.2) * (open ? 0.26 : 0.20)
    j = at + i
    break if j >= l.length
    # Hats sit off-centre, alternating, so the kit occupies width the chord does not.
    l[j] += s * (seed.even? ? 1.15 : 0.72)
    r[j] += s * (seed.even? ? 0.72 : 1.15)
  end
end

# One bar of the kit over a chord of `secs`, with the two grids disagreeing.
def drums_for_bar!(l, r, offset, secs, bar_index)
  sixteenth = (RATE * secs / 16.0)
  place = ->(step, nudge) { (offset + (step + nudge) * sixteenth).to_i }

  kicks = [0, 3, 6, 10].then { |k| bar_index.odd? ? k + [14] : k }
  kicks.each { |st| kick!(l, r, place.(st, KICK_EARLY), secs) }

  16.step(0, -2) { |_| nil }
  (0...16).step(2) do |st|
    open = st == 10
    hat!(l, r, place.(st, HAT_LATE), open, st + bar_index)
  end
  # Ghosts on the far side of the beat, quieter and later still.
  [5, 13].each { |st| hat!(l, r, place.(st, GHOST_LATE), false, st + bar_index + 7) }
end

# ringtone.tools, reimplemented on the buffer instead of through ffmpeg.
#
# lib/devices.rb carries these as file-level devices that shell out. Nothing in
# this stream is a file until the very end, so the ideas are rebuilt here on the
# sample arrays directly -- same devices, no subprocess per chord.

# Copy Machine: the same audio played n times at once at different speeds. The
# copies drift apart in time as well as pitch, so a chord stops being a chord
# and becomes a cloud of itself. Harmonic ratios, because arbitrary ones just
# sound out of tune.
COPY_RATIOS = [1.0, 1.5, 0.75, 2.0, 0.5, 1.3333].freeze

def copy_machine!(l, r, copies: 4, reverse: 0.2, width: 0.85)
  n = l.length
  src_l = l.dup
  src_r = r.dup
  (1...[copies, COPY_RATIOS.length].min).each do |c|
    ratio = COPY_RATIOS[c]
    rev = ((c * 0.37) % 1.0) < reverse
    pan = ((c.to_f / copies) - 0.5) * 2 * width
    lg = Math.cos((pan + 1) * Math::PI / 4)
    rg = Math.sin((pan + 1) * Math::PI / 4)
    gain = 0.62 / Math.sqrt(copies)
    n.times do |i|
      pos = i * ratio
      j = pos.to_i
      next if j >= n - 1

      k = rev ? (n - 1 - j) : j
      frac = pos - j
      a = src_l[k] * (1 - frac) + src_l[[k + (rev ? -1 : 1), 0].max.clamp(0, n - 1)] * frac
      b = src_r[k] * (1 - frac) + src_r[[k + (rev ? -1 : 1), 0].max.clamp(0, n - 1)] * frac
      l[i] += a * gain * lg
      r[i] += b * gain * rg
    end
  end
end

# Low Pass Gate: a Buchla vactrol, where the filter closes as the note decays.
# It is a NOTE device -- what makes it an LPG rather than a filter is that the
# cutoff and the amplitude fall together, so the sound gets darker as it gets
# quieter, the way a struck thing does.
def lpg!(l, r, decay_ms: 240.0, droop: 2.2, blend: 0.7)
  n = l.length
  tau = (decay_ms / 1000.0) * RATE
  zl = 0.0
  zr = 0.0
  n.times do |i|
    env = Math.exp(-i / tau)**(1.0 / droop)
    # Cutoff rides the envelope: wide open at the strike, nearly shut by the tail.
    cut = 0.06 + 0.72 * env
    zl += cut * (l[i] - zl)
    zr += cut * (r[i] - zr)
    l[i] = l[i] * (1 - blend) + zl * env * blend
    r[i] = r[i] * (1 - blend) + zr * env * blend
  end
end

# P_4L: seven Plaits oscillators behind one macro knob. The macro here picks
# how much odd-harmonic content rides on top of the sine -- 0 is the bare
# fundamental, 1 is close to a square. One knob, seven positions.
def plaits_partials(macro)
  depth = macro.clamp(0.0, 1.0)
  [[1.0, 1.0], [3.0, 0.34 * depth], [5.0, 0.19 * depth],
   [7.0, 0.12 * depth], [9.0, 0.08 * depth]]
end

# Space Echo: an RE-201 is three playback heads down one tape loop, with the
# feedback path going back to the record head. What makes it tape and not a
# digital delay is that every repeat comes back darker, and that the tape
# speed is never exactly steady -- so the repeats drift in pitch. Both are
# here: a one-pole per repeat, and a slow wow on the read position.
def space_echo!(l, r, time_s: 0.42, feedback: 0.55, heads: 3, mix: 0.42)
  n = l.length
  base = (RATE * time_s)
  wow_rate = 2 * Math::PI * 0.7 / RATE
  dl = Array.new(n, 0.0)
  dr = Array.new(n, 0.0)
  (1..heads).each do |h|
    lp_l = 0.0
    lp_r = 0.0
    gain = feedback**h
    next if gain < 0.02

    n.times do |i|
      # Wow: the read head is never exactly where the maths says it is.
      wow = Math.sin(wow_rate * i + h) * (base * 0.004)
      pos = i - (base * h + wow)
      next if pos < 1

      j = pos.to_i
      frac = pos - j
      a = l[j] * (1 - frac) + l[j - 1] * frac
      b = r[j] * (1 - frac) + r[j - 1] * frac
      # Each repeat darker than the last -- the tape losing its top.
      cut = 0.42 - h * 0.07
      lp_l += cut * (a - lp_l)
      lp_r += cut * (b - lp_r)
      # Heads alternate sides, which is what makes a Space Echo wide.
      sw = h.odd? ? 1.25 : 0.7
      dl[i] += lp_l * gain * sw
      dr[i] += lp_r * gain * (2.0 - sw)
    end
  end
  n.times do |i|
    l[i] += dl[i] * mix
    r[i] += dr[i] * mix
  end
end

def write_wav(path, left, right)
  n = left.length
  File.open(path, "wb") do |f|
    f.write("RIFF"); f.write([36 + n * 4].pack("V")); f.write("WAVEfmt ")
    f.write([16, 1, 2, RATE, RATE * 4, 4, 16].pack("Vv v V V v v"))
    f.write("data"); f.write([n * 4].pack("V"))
    buf = String.new(capacity: n * 4)
    n.times do |i|
      buf << [(left[i] * 32_767).clamp(-32_767, 32_767).to_i,
              (right[i] * 32_767).clamp(-32_767, 32_767).to_i].pack("s<s<")
    end
    f.write(buf)
  end
end

# One voice, rendered into the mix with whatever the treatment asks for.
def add_voice!(left, right, hz, amp, pan, n, treat, vi, total, entry = 0)
  return if hz <= 0

  lg = Math.cos((pan + 1) * Math::PI / 4)
  rg = Math.sin((pan + 1) * Math::PI / 4)
  base = 2 * Math::PI * (hz * PITCH) / RATE

  # Detunes: a single sine is inert, two a few cents apart beat against each
  # other, and beating is what makes a pure tone sound alive rather than tested.
  detunes = case treat
            when :shimmer then [0.0, 5.0, -7.0]
            when :bloom then [0.0, 3.0]
            else [0.0]
            end
  detunes.each do |cents|
    step = base * (2.0**(cents / 1200.0))
    ph = 0.0
    va = amp / detunes.length
    trem_rate = 2 * Math::PI * (0.7 + vi * 0.13) / RATE
    drift_rate = 2 * Math::PI * (0.05 + vi * 0.017) / RATE
    partials = treat == :plaits ? plaits_partials(0.35 + (vi.to_f / [total, 1].max) * 0.6) : [[1.0, 1.0]]
    n.times do |i|
      next if i < entry
      s = partials.sum { |(mult, w)| Math.sin(ph * mult) * w } / partials.sum { |(_, w)| w }
      ph += step
      g = va
      case treat
      when :tremolo then g *= 0.62 + 0.38 * Math.sin(trem_rate * i + vi)
      when :swell   then g *= [(i - entry).to_f / (n * 0.55), 1.0].min
      when :fugue   then g *= [(i - entry).to_f / (RATE * 0.09), 1.0].min
      when :bloom   then g *= 0.45 + 0.55 * (i.to_f / n)
      end
      if treat == :drift
        d = Math.sin(drift_rate * i + vi * 1.7) * 0.45
        pl = Math.cos((pan + d + 1) * Math::PI / 4)
        pr = Math.sin((pan + d + 1) * Math::PI / 4)
        left[i] += s * g * pl
        right[i] += s * g * pr
      else
        left[i] += s * g * lg
        right[i] += s * g * rg
      end
    end
  end
end

def chord_samples(hzs, bass_hz, secs, treat)
  n = (RATE * secs).to_i
  left = Array.new(n, 0.0)
  right = Array.new(n, 0.0)
  voices = hzs.map(&:to_f).reject { |h| h <= 0 }.sort
  bass = bass_hz.to_f
  extra = []
  extra << [bass / 2.0, 0.55] if treat == :sub && bass > 40
  extra << [voices.last * 2.0, 0.30] if treat == :halo && voices.any?
  all = voices.map { |h| [h, 1.0] }
  all << [bass, 0.9] if bass > 0
  all += extra
  return [left, right] if all.empty?

  amp = 0.32 / Math.sqrt(all.length)
  all.each_with_index do |(hz, w), vi|
    pan = all.length > 1 ? ((vi.to_f / (all.length - 1)) - 0.5) * 0.72 : 0.0
    # Staggered entries: each voice comes in a beat after the one below it,
    # which is imitation rather than a block chord.
    entry = treat == :fugue ? (RATE * secs * 0.16 * vi).to_i.clamp(0, n - 1) : 0
    add_voice!(left, right, hz, amp * w, pan, n, treat, vi, all.length, entry)
  end
  [left, right]
end

# Overlap-add: the tail of what is already written fades out under the head of
# what comes next, so one progression becomes the next without a seam.
def crossfade_append!(buf_l, buf_r, add_l, add_r, xfade_samples)
  ov = [xfade_samples, buf_l.length, add_l.length].min
  if ov.positive?
    start = buf_l.length - ov
    ov.times do |i|
      t = i.to_f / ov
      buf_l[start + i] = buf_l[start + i] * (1 - t) + add_l[i] * t
      buf_r[start + i] = buf_r[start + i] * (1 - t) + add_r[i] * t
    end
    buf_l.concat(add_l[ov..] || [])
    buf_r.concat(add_r[ov..] || [])
  else
    buf_l.concat(add_l)
    buf_r.concat(add_r)
  end
end

cfg = dilla_resolve_config
names = CHORD_PROGRESSIONS.keys
xf = (RATE * XFADE).to_i
round = 0

loop do
  round += 1
  # Reordered every pass so a long listen is not the same sequence twice.
  order = round == 1 ? names : names.shuffle(random: Random.new(round * 7919))
  order.each_slice(PER_FILE).with_index do |group, gi|
    break if File.exist?(STOP)

    l = []
    r = []
    played = []
    group.each_with_index do |name, ni|
      pads = begin
        p0 = dilla_progression(name)
        next if p0.nil? || p0.empty?
        p1, = DillaHarmony.beautify_pipeline(p0, cfg.merge(progression: name))
        p1 && !p1.empty? ? p1 : p0
      rescue StandardError
        next
      end

      treat = TREATMENTS[(gi * PER_FILE + ni) % TREATMENTS.length]
      played << "#{name}/#{treat}"
      pads.each_with_index do |c, bar|
        cl, cr = chord_samples(Array(c[:hz]), c[:bass_hz], SECS, treat)
        drums_for_bar!(cl, cr, 0, SECS, bar) unless ENV["SINE_DRUMS"] == "0"
        case treat
        when :copymachine then copy_machine!(cl, cr, copies: 4)
        when :cloud then copy_machine!(cl, cr, copies: 6, reverse: 0.45, width: 1.0)
        when :lpg then lpg!(cl, cr)
        when :echo then space_echo!(cl, cr, time_s: SECS / 6.0, feedback: 0.58)
        when :dub then space_echo!(cl, cr, time_s: SECS / 3.0, feedback: 0.72, heads: 4, mix: 0.6)
        end
        crossfade_append!(l, r, cl, cr, xf)
      end
    end
    next if l.empty?

    # Top and tail so the file itself does not click in or out.
    edge = (RATE * 0.05).to_i
    edge.times do |i|
      g = i.to_f / edge
      l[i] *= g; r[i] *= g
      l[-1 - i] *= g; r[-1 - i] *= g
    end

    wav = File.join(OUT, "now_#{gi % 2}.wav")
    write_wav(wav, l, r)
    File.write(PROGRESS, "pass #{round}  #{played.join('  ->  ')}\n")
    system("/usr/bin/afplay", wav)
  end
  break if File.exist?(STOP)
end
