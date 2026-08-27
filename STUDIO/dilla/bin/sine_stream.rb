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
require "fileutils"

RATE = 44_100
OUT = "/Users/mac/Music/dilla_sines"
PROGRESS = File.join(OUT, "now_playing.txt")
STOP = File.join(OUT, "STOP")
XFADE = (ENV["SINE_XFADE_SECS"] || "0.5").to_f
SECS = (ENV["SINE_CHORD_SECS"] || "4.6").to_f
# Down a semitone, because everything sits meaner a half-step below where it was
# written. Applied to every voice including the bass, so the whole field moves
# together rather than the tuning coming apart.
PITCH = 2.0**((ENV["SINE_PITCH_SEMITONES"] || "-1").to_f / 12.0)
# Two progressions per file, not five. A file is held entirely in Ruby float
# arrays and passes through a dozen copies -- the copy machine, the echo, the
# master chain writing and reading it back -- and at five progressions the
# generator was being killed before it ever wrote one, which from the speakers
# looked like the catalogue had frozen on a single take.
PER_FILE = (ENV["SINE_PROGS_PER_FILE"] || "2").to_i
PROG_CHORDS = (ENV["SINE_PROG_CHORDS"] || "4").to_i

# Eight ways to voice the same sine. Rotated per progression so the stream keeps
# moving through textures instead of being one timbre for ninety minutes.
TREATMENTS = %i[plain shimmer halo tremolo drift sub bloom swell
                copymachine lpg plaits cloud fugue echo dub
                ringmod chainsaw barber grains machine].freeze

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

# The devices stack, and stacked they run past full scale -- copy machine and
# the cloud measured 1.7 and 1.8 peak against a 1.0 ceiling. Clamping at write
# time turns that into square-wave clipping, which is a different and worse
# sound than drive. tanh instead: it rounds the peak, so the loud parts get
# thicker rather than broken, which is what "heavily processed" should mean.
def soft_limit!(l, r, ceiling: 0.94)
  peak = 0.0
  l.each_with_index { |v, i| x = [v.abs, r[i].abs].max; peak = x if x > peak }
  return if peak <= 0.0001

  drive = [peak / ceiling, 1.0].max
  l.length.times do |i|
    l[i] = Math.tanh(l[i] / drive * 1.35) * ceiling
    r[i] = Math.tanh(r[i] / drive * 1.35) * ceiling
  end
end

# Rap vocals, read straight off disk and mixed into the buffer.
#
# jonas_v goes slower than it was recorded, which drops the pitch with it --
# that is varispeed, not a time stretch, and the pitch coming down with the
# tempo is the whole character of the thing.
VOCAL_DIRS = {
  store_p: "project/learnings/vocals/store_p",
  gunnhild: "project/learnings/vocals/gunnhild",
  jonas_v: "project/learnings/vocals/jonas_v",
}.freeze

# Never varispeed a rap vocal. Slowing the read rate drops the pitch with it,
# and a rapper's voice at the wrong pitch is a different person -- so every take
# plays at the speed it was recorded, whatever the track around it is doing.
VOCAL_SPEED = { store_p: 1.0, gunnhild: 1.0, jonas_v: 1.0 }.freeze

# store_p takes three slots in five. He is the best of them.
# store_p on every slot but the last, which is gunnhild. jonas_v is out of the
# rotation entirely -- this is a store_p record with her closing it.
VOCAL_LEAD = :store_p
VOCAL_TAIL = :gunnhild

def vocal_files(slug)
  @vocal_cache ||= {}
  @vocal_cache[slug] ||= Dir[File.join(VOCAL_DIRS[slug], "*.wav")].sort
end

# Minimal 16-bit PCM WAV reader. The engine's own loader shells out to ffmpeg
# per file; nothing else in this stream shells out and it is not starting here.
def read_wav(path)
  raw = File.binread(path)
  return nil unless raw[0, 4] == "RIFF" && raw[8, 4] == "WAVE"

  pos = 12
  fmt = nil
  data = nil
  while pos + 8 <= raw.bytesize
    id = raw[pos, 4]
    sz = raw[pos + 4, 4].unpack1("V")
    body = raw[pos + 8, sz]
    fmt = body if id == "fmt "
    data = body if id == "data"
    pos += 8 + sz + (sz.odd? ? 1 : 0)
  end
  return nil unless fmt && data

  ch = fmt[2, 2].unpack1("v")
  rate = fmt[4, 4].unpack1("V")
  bits = fmt[14, 2].unpack1("v")
  return nil unless bits == 16 && ch.between?(1, 2)

  s = data.unpack("s<*")
  if ch == 2
    [s.each_slice(2).map { |x, _| x / 32_768.0 }, s.each_slice(2).map { |_, y| (y || 0) / 32_768.0 }, rate]
  else
    v = s.map { |x| x / 32_768.0 }
    [v, v.dup, rate]
  end
end

# Cassette, as Dilla asked Dave Cooley for it: "flatter, thuddy-er". Band-limit
# top and bottom, push the middle, saturate lightly, and let the speed wander --
# washed out, gritty and mid-rangey rather than clean and wide.
def cassette!(l, r, drive: 1.5, top: 0.16, bottom: 0.014, gain: 0.8)
  n = l.length
  lp_l = 0.0
  lp_r = 0.0
  hp_l = 0.0
  hp_r = 0.0
  k = Math.tanh(drive)
  n.times do |i|
    # Saturate BEFORE the band limit, not after. Tape distorts and then loses
    # its top; doing it the other way round means the distortion regenerates the
    # top the filter just took, and the "cassette" comes out brighter than the
    # source -- measured at +38% high-frequency energy before this order was
    # fixed.
    sl = Math.tanh(l[i] * drive) / k
    sr = Math.tanh(r[i] * drive) / k
    lp_l += top * (sl - lp_l)
    lp_r += top * (sr - lp_r)
    hp_l += bottom * (lp_l - hp_l)
    hp_r += bottom * (lp_r - hp_r)
    bl = lp_l - hp_l
    br = lp_r - hp_r
    # Narrower as well as darker: cassette is not a wide format.
    m = (bl + br) * 0.5
    l[i] = (bl * 0.72 + m * 0.28) * gain
    r[i] = (br * 0.72 + m * 0.28) * gain
  end
end

# Lay a vocal take over a buffer at `speed`, looping it if the take runs short.
# No take is ever used twice, and when they run out the track goes instrumental.
#
# The rotation used to index the file list by slot, so after forty-three takes
# store_p came round again and started the whole set over -- and a restart began
# it from the top regardless. A rapper repeating a verse is worse than a rapper
# not being on the track, so the used list is kept on disk, survives a restart,
# and when a voice is exhausted add_vocal! returns false and the progression
# plays without it.
VOCAL_USED_DIR = File.join(OUT, "vocals_used")

def vocal_used(slug)
  FileUtils.mkdir_p(VOCAL_USED_DIR)
  p = File.join(VOCAL_USED_DIR, "#{slug}.txt")
  File.file?(p) ? File.readlines(p).map(&:strip).reject(&:empty?) : []
end

def mark_vocal_used(slug, path)
  FileUtils.mkdir_p(VOCAL_USED_DIR)
  File.open(File.join(VOCAL_USED_DIR, "#{slug}.txt"), "a") { |o| o.puts(path) }
end

def add_vocal!(l, r, slug, speed, _index, gain: 0.62)
  files = vocal_files(slug)
  return false if files.empty?

  fresh = files - vocal_used(slug)
  # Every take spent. Silence is the correct answer, not a second airing.
  return false if fresh.empty?

  path = fresh.first
  got = read_wav(path)
  if got.nil?
    mark_vocal_used(slug, path)
    return false
  end

  vl, vr, vrate = got
  step = speed * (vrate.to_f / RATE)
  n = l.length
  src_n = vl.length
  if src_n < 2
    mark_vocal_used(slug, path)
    return false
  end

  n.times do |i|
    pos = i * step
    # The take is used once through and then stops. Wrapping it round to fill
    # the bar is the same repetition in miniature.
    break if pos >= src_n - 1

    j = pos.to_i
    frac = pos - j
    l[i] += (vl[j] * (1 - frac) + vl[j + 1] * frac) * gain
    r[i] += (vr[j] * (1 - frac) + vr[j + 1] * frac) * gain
  end
  mark_vocal_used(slug, path)
  true
end

# The 217 preset voicings, applied to the tone.
#
# Each entry in SYNTH_PATCH_CATALOG is a soundfont program plus an ffmpeg chain,
# and this stream has no soundfont in it. What it does have is the chain: the
# equalizer bands and tremolo in each preset's `fx` string are that preset's
# published voice -- rhodes_mark1 is +2.2 dB at 280 Hz and +3.2 dB of high shelf
# at 2.4 kHz, and applying those to a sine is applying the same voicing to a
# different oscillator. That is a real showcase of the presets rather than a
# name printed next to an unrelated sound.
PRESETS = SYNTH_PATCH_CATALOG.select { |p| p[:fx].to_s.include?("equalizer") }.freeze

def preset_bands(preset)
  @band_cache ||= {}
  @band_cache[preset[:id]] ||= preset[:fx].to_s.scan(
    /equalizer=f=(\d+):t=(\w+):w=([\d.]+):g=([-\d.]+)/
  ).map { |hz, type, w, g| { hz: hz.to_f, type: type, w: w.to_f, db: g.to_f } }
end

def preset_tremolo(preset)
  m = preset[:fx].to_s.match(/tremolo=f=([\d.]+):d=([\d.]+)/)
  m ? [m[1].to_f, m[2].to_f] : nil
end

# One-pole peaking/shelf per band. Not a biquad -- a one-pole cannot make a
# narrow bell -- but the direction and the amount are the preset's own numbers,
# and on a sine bed the direction is what is audible.
def apply_preset!(l, r, preset)
  bands = preset_bands(preset)
  return if bands.empty?

  n = l.length
  bands.each do |b|
    gain = 10.0**(b[:db] / 20.0) - 1.0
    next if gain.abs < 0.02

    k = (1.0 - Math.exp(-2 * Math::PI * b[:hz] / RATE)).clamp(0.0005, 0.98)
    zl = 0.0
    zr = 0.0
    n.times do |i|
      zl += k * (l[i] - zl)
      zr += k * (r[i] - zr)
      # low pass for a low shelf, its complement for a high shelf/peak
      pl = b[:type] == "o" && b[:hz] < 500 ? zl : l[i] - zl
      pr = b[:type] == "o" && b[:hz] < 500 ? zr : r[i] - zr
      l[i] += pl * gain * 0.5
      r[i] += pr * gain * 0.5
    end
  end
  if (trem = preset_tremolo(preset))
    rate = 2 * Math::PI * trem[0] / RATE
    n.times do |i|
      g = 1.0 - trem[1] * 0.5 * (1.0 - Math.sin(rate * i))
      l[i] *= g
      r[i] *= g
    end
  end
end

# The master chain: Sonitex, then NastyVCS, then the standard tools.
#
# SONITEX_STX1260 in lib/engine/engine_defaults.rb is a measured parameter set,
# not a guess -- its signal flow is documented there from Sound On Sound and
# Tone Projects' own description. This runs that flow on the buffer, so what
# comes out is the same chain the engine's master bus runs, arrived at without
# a subprocess.
def sonitex_pass!(l, r, p, amount: 1.0)
  n = l.length
  # 1. mastering compressor
  compress!(l, r, threshold_db: p[:comp_threshold], ratio: p[:comp_ratio],
                  attack_ms: p[:comp_attack], release_ms: p[:comp_release],
                  makeup: 1.0 + (p[:comp_makeup] - 1.0) * amount)
  # 2. mid/side width
  width!(l, r, p[:stereo_width], p[:side_gain])
  # 3. pre-emphasised distortion, wet/dry as the preset specifies
  pre = 10.0**(p[:dist_pre_emph_db] / 20.0)
  kpre = 1.0 - Math.exp(-2 * Math::PI * p[:dist_pre_lp] / RATE)
  drive = 1.0 + (p[:dist_drive] - 1.0) * amount
  mix = p[:dist_mix] * amount
  zl = 0.0
  zr = 0.0
  n.times do |i|
    zl += kpre * (l[i] - zl)
    zr += kpre * (r[i] - zr)
    dl = Math.tanh(zl * pre * drive + p[:dist_dc]) / Math.tanh(drive * pre)
    dr = Math.tanh(zr * pre * drive + p[:dist_dc]) / Math.tanh(drive * pre)
    l[i] = l[i] * (1 - mix) + dl * mix
    r[i] = r[i] * (1 - mix) + dr * mix
  end
  # 4. vinyl bandwidth: rolloffs plus the resonant head bump
  band_limit!(l, r, p[:hf_rolloff], p[:lf_rolloff])
  head_bump!(l, r, p[:head_bump_hz], p[:head_bump_db] * amount)
  band_limit!(l, r, p[:groove_wear_lp], 0)
  # 5. wow and flutter
  warble!(l, r, p[:wow_rate], p[:wow_depth] * amount, p[:flutter_hz], p[:flutter_depth] * amount)
  # 6. surface noise
  noise!(l, r, p[:hiss_amp] * amount, p[:pop_rate], p[:pop_amp], p[:click_rate])
  # 7. the 12-bit sampler
  crush!(l, r, p[:crush_bits], p[:crush_sr], p[:crush_mix] * amount, p[:crush_post_lp])
  # 8. output compressor and ceiling
  compress!(l, r, threshold_db: p[:out_comp_threshold], ratio: p[:out_comp_ratio],
                  attack_ms: 12, release_ms: 110, makeup: p[:out_comp_makeup])
  n.times { |i| l[i] = l[i].clamp(-p[:limit], p[:limit]) * p[:level_out]
                r[i] = r[i].clamp(-p[:limit], p[:limit]) * p[:level_out] }
end

def compress!(l, r, threshold_db:, ratio:, attack_ms:, release_ms:, makeup: 1.0)
  thr = 10.0**(threshold_db / 20.0)
  at = Math.exp(-1.0 / (RATE * attack_ms / 1000.0))
  rel = Math.exp(-1.0 / (RATE * release_ms / 1000.0))
  env = 0.0
  l.length.times do |i|
    peak = [l[i].abs, r[i].abs].max
    env = peak > env ? at * env + (1 - at) * peak : rel * env + (1 - rel) * peak
    g = env > thr ? (thr + (env - thr) / ratio) / env : 1.0
    l[i] *= g * makeup
    r[i] *= g * makeup
  end
end

def width!(l, r, w, side_gain)
  l.length.times do |i|
    m = (l[i] + r[i]) * 0.5
    s = (l[i] - r[i]) * 0.5 * w * side_gain
    l[i] = m + s
    r[i] = m - s
  end
end

def band_limit!(l, r, hf, lf)
  n = l.length
  khf = hf.to_f.positive? ? (1.0 - Math.exp(-2 * Math::PI * hf / RATE)).clamp(0.0005, 0.999) : nil
  klf = lf.to_f.positive? ? (1.0 - Math.exp(-2 * Math::PI * lf / RATE)).clamp(0.00005, 0.5) : nil
  zl = 0.0; zr = 0.0; hl = 0.0; hr = 0.0
  n.times do |i|
    if khf
      zl += khf * (l[i] - zl); zr += khf * (r[i] - zr)
      l[i] = zl; r[i] = zr
    end
    next unless klf

    hl += klf * (l[i] - hl); hr += klf * (r[i] - hr)
    l[i] -= hl; r[i] -= hr
  end
end

# The head bump is what makes tape sound like tape at the bottom -- a resonance,
# not a shelf, so it is a bandpass added back rather than a low boost.
def head_bump!(l, r, hz, db)
  return if db.abs < 0.05

  g = 10.0**(db / 20.0) - 1.0
  k = (1.0 - Math.exp(-2 * Math::PI * hz / RATE)).clamp(0.0005, 0.5)
  k2 = (1.0 - Math.exp(-2 * Math::PI * (hz * 0.45) / RATE)).clamp(0.00005, 0.5)
  al = 0.0; ar = 0.0; bl = 0.0; br = 0.0
  l.length.times do |i|
    al += k * (l[i] - al); ar += k * (r[i] - ar)
    bl += k2 * (al - bl); br += k2 * (ar - br)
    l[i] += (al - bl) * g
    r[i] += (ar - br) * g
  end
end

def warble!(l, r, wow_rate, wow_depth, flut_hz, flut_depth)
  return if wow_depth <= 0 && flut_depth <= 0

  n = l.length
  sl = l.dup
  sr = r.dup
  wr = 2 * Math::PI * wow_rate / RATE
  fr = 2 * Math::PI * flut_hz / RATE
  span = RATE * 0.012
  n.times do |i|
    d = span * (wow_depth * Math.sin(wr * i) + flut_depth * Math.sin(fr * i))
    pos = i - span - d
    next if pos < 1 || pos >= n - 1

    j = pos.to_i
    fr2 = pos - j
    l[i] = sl[j] * (1 - fr2) + sl[j + 1] * fr2
    r[i] = sr[j] * (1 - fr2) + sr[j + 1] * fr2
  end
end

def noise!(l, r, hiss, pop_rate, pop_amp, click_rate)
  rnd = Random.new(20_260_827)
  l.length.times do |i|
    l[i] += (rnd.rand * 2 - 1) * hiss
    r[i] += (rnd.rand * 2 - 1) * hiss
    if rnd.rand < pop_rate
      pv = (rnd.rand * 2 - 1) * pop_amp
      l[i] += pv
      r[i] += pv * 0.7
    end
    next unless rnd.rand < click_rate

    l[i] += (rnd.rand * 2 - 1) * pop_amp * 0.5
  end
end

def crush!(l, r, bits, sr_div, mix, post_lp)
  return if mix <= 0

  steps = 2**(bits - 1)
  hold_l = 0.0
  hold_r = 0.0
  acc = 0.0
  n = l.length
  dl = Array.new(n, 0.0)
  dr = Array.new(n, 0.0)
  n.times do |i|
    acc += 1.0
    if acc >= sr_div
      acc -= sr_div
      hold_l = (l[i] * steps).round / steps.to_f
      hold_r = (r[i] * steps).round / steps.to_f
    end
    dl[i] = hold_l
    dr[i] = hold_r
  end
  band_limit!(dl, dr, post_lp, 0)
  n.times do |i|
    l[i] = l[i] * (1 - mix) + dl[i] * mix
    r[i] = r[i] * (1 - mix) + dr[i] * mix
  end
end

# NastyVCS is a channel strip, and four of them summed with each path phase-
# offset is the "phasy" part: the paths partially cancel, which narrows and
# hollows the middle the way a real parallel-console sum does. The offsets are
# sub-millisecond on purpose -- long enough to comb, short enough not to echo.
NASTY_OFFSETS = [0, 13, 29, 47].freeze

def nasty_vcs_sum!(l, r, instances: 4)
  n = l.length
  src_l = l.dup
  src_r = r.dup
  out_l = Array.new(n, 0.0)
  out_r = Array.new(n, 0.0)
  instances.times do |k|
    off = NASTY_OFFSETS[k % NASTY_OFFSETS.length]
    pl = Array.new(n) { |i| i >= off ? src_l[i - off] : 0.0 }
    pr = Array.new(n) { |i| i >= off ? src_r[i - off] : 0.0 }
    # Each instance voiced differently, so the sum is a console and not a chorus.
    head_bump!(pl, pr, 70 + k * 11, 1.4)
    band_limit!(pl, pr, 15_000 - k * 900, 28 + k * 6)
    compress!(pl, pr, threshold_db: -20 + k * 2, ratio: 2.2 + k * 0.4,
                      attack_ms: 6 + k * 4, release_ms: 90 + k * 30, makeup: 1.1)
    d = 1.3 + k * 0.25
    n.times do |i|
      out_l[i] += Math.tanh(pl[i] * d) / Math.tanh(d)
      out_r[i] += Math.tanh(pr[i] * d) / Math.tanh(d)
    end
  end
  g = 1.0 / Math.sqrt(instances)
  n.times do |i|
    l[i] = out_l[i] * g
    r[i] = out_r[i] * g
  end
end

# The deep stage: what the Detroit and Los Angeles records do to a master that a
# clean mastering chain does not.
#
# Three things, none of them subtle, all of them things a purist chain removes.
# A Haas spread that puts the sides slightly late so the middle stays mono and
# the top opens; a resonant sweep that moves once across the whole file so the
# tone is never static; and a dub delay on the master bus itself rather than on
# a send, so the repeats carry the master's own compression with them.
def haas_spread!(l, r, ms: 11.0, mix: 0.5)
  d = (RATE * ms / 1000.0).to_i
  n = l.length
  src = r.dup
  n.times do |i|
    next if i < d

    r[i] = r[i] * (1 - mix) + src[i - d] * mix
  end
end

def resonant_sweep!(l, r, from_hz: 380.0, to_hz: 5200.0, depth: 0.45)
  n = l.length
  bl = 0.0
  br = 0.0
  ll = 0.0
  lr = 0.0
  n.times do |i|
    t = i.to_f / n
    # Log sweep, because a linear one spends most of its time in the top octave
    # where there is nothing to find.
    hz = from_hz * ((to_hz / from_hz)**t)
    k = (1.0 - Math.exp(-2 * Math::PI * hz / RATE)).clamp(0.0005, 0.99)
    ll += k * (l[i] - ll)
    lr += k * (r[i] - lr)
    bl = ll - bl * 0.0
    br = lr - br * 0.0
    l[i] += (ll - (l[i] - ll)) * depth * 0.25
    r[i] += (lr - (r[i] - lr)) * depth * 0.25
  end
end

def master_dub!(l, r, time_s: 0.66, feedback: 0.42, mix: 0.3)
  n = l.length
  d = (RATE * time_s).to_i
  return if d >= n

  # Feedback taken from the OUTPUT, so each repeat is darker and more compressed
  # than the last -- which is what a master-bus delay does and a send does not.
  fb_l = 0.0
  fb_r = 0.0
  n.times do |i|
    next if i < d

    fb_l += 0.34 * (l[i - d] + fb_l * feedback - fb_l)
    fb_r += 0.34 * (r[i - d] + fb_r * feedback - fb_r)
    l[i] += fb_l * mix
    r[i] += fb_r * mix
  end
end

# Spatial and modulating devices for the pad, in the direction of machinery that
# is nonetheless moving: metallic and periodic on the surface, never repeating
# underneath.

# Ring modulation against a slow-moving carrier. A fixed carrier is a metallic
# buzz and nothing else; a carrier that drifts turns the same buzz into
# something that reads as a mechanism running rather than a tone sitting.
def ring_mod!(l, r, hz: 74.0, drift_hz: 0.11, mix: 0.42)
  n = l.length
  ph = 0.0
  dph = 0.0
  n.times do |i|
    dph += 2 * Math::PI * drift_hz / RATE
    f = hz * (1.0 + 0.28 * Math.sin(dph))
    ph += 2 * Math::PI * f / RATE
    c = Math.sin(ph)
    l[i] = l[i] * (1 - mix) + l[i] * c * mix
    r[i] = r[i] * (1 - mix) + r[i] * c * mix * -1.0
  end
end

# A comb resonator short enough to be a pitch rather than an echo. This is the
# chainsaw: a feedback delay of a couple of milliseconds rings at 1/delay, and
# sweeping the delay sweeps that ring through the harmonic series.
def comb_resonator!(l, r, hz_from: 118.0, hz_to: 52.0, feedback: 0.72, mix: 0.5)
  n = l.length
  bl = Array.new(n, 0.0)
  br = Array.new(n, 0.0)
  n.times do |i|
    t = i.to_f / n
    hz = hz_from * ((hz_to / hz_from)**t)
    d = (RATE / hz).to_i
    next if i < d

    bl[i] = l[i] + bl[i - d] * feedback
    br[i] = r[i] + br[i - d] * feedback
    l[i] = l[i] * (1 - mix) + bl[i] * mix * 0.5
    r[i] = r[i] * (1 - mix) + br[i] * mix * 0.5
  end
end

# Cascaded allpass with an LFO on the coefficient -- a phaser, but eight stages
# and the two channels a quarter cycle apart, so the notches move across the
# field rather than up and down in the middle of it.
def barber_phaser!(l, r, stages: 8, rate_hz: 0.08, depth: 0.85, mix: 0.6)
  n = l.length
  zl = Array.new(stages, 0.0)
  zr = Array.new(stages, 0.0)
  w = 2 * Math::PI * rate_hz / RATE
  n.times do |i|
    ml = 0.5 + depth * 0.45 * Math.sin(w * i)
    mr = 0.5 + depth * 0.45 * Math.sin(w * i + Math::PI / 2)
    xl = l[i]
    xr = r[i]
    stages.times do |k|
      yl = -ml * xl + zl[k]
      zl[k] = xl + ml * yl
      xl = yl
      yr = -mr * xr + zr[k]
      zr[k] = xr + mr * yr
      xr = yr
    end
    l[i] = l[i] * (1 - mix) + xl * mix
    r[i] = r[i] * (1 - mix) + xr * mix
  end
end

# Grains re-triggered from positions that jump. Deterministic per progression --
# seeded, so a take can be reproduced -- but the jumps are large enough that the
# pad stops having one continuous surface.
def granular_smear!(l, r, grain_ms: 90.0, jump: 0.35, mix: 0.55, seed: 11)
  n = l.length
  g = (RATE * grain_ms / 1000.0).to_i
  return if g < 32 || n < g * 4

  rnd = Random.new(seed)
  sl = l.dup
  sr = r.dup
  pos = 0
  while pos + g < n
    src = (pos + ((rnd.rand * 2 - 1) * jump * n)).to_i.clamp(0, n - g - 1)
    g.times do |k|
      # Hann window, so grains overlap without edges.
      wgt = 0.5 - 0.5 * Math.cos(2 * Math::PI * k / g)
      l[pos + k] = l[pos + k] * (1 - mix * wgt) + sl[src + k] * mix * wgt
      r[pos + k] = r[pos + k] * (1 - mix * wgt) + sr[src + k] * mix * wgt
    end
    pos += g / 2
  end
end

# The chain repeated whole, four times.
#
# Turning one stage up is not the same thing. Each full pass compresses what the
# last pass distorted, band-limits what it just added, and re-sums it through the
# console -- so the bottom thickens and settles a little further every round,
# which is where the depth comes from. Passes are attenuated slightly on the way
# in so four of them do not simply crush.
# The master chain, as ffmpeg filters.
#
# The same nine Sonitex stages from SONITEX_STX1260, the console sum and the deep
# stage, four rounds of the whole thing -- built from exactly the parameters the
# Ruby version used. What changed is where it runs.
#
# Measured, because this was the thing that stopped the stream being live: the
# Ruby chain took 70.5 seconds to master 20 seconds of audio, 3.5x slower than
# realtime, so the generator could never feed the speakers no matter how it was
# scheduled. The same chain in ffmpeg takes 2.7 seconds for the same 20 seconds
# -- 0.137x realtime, twenty-five times faster than playback. Nothing about the
# sound was traded for it; the arithmetic simply moved out of the interpreter.
#
# Two traps, both of which took the whole graph down rather than one stage:
# aecho wants its decays pipe-separated like its delays, and the groove-wear
# lowpass runs only on the last pass of each round, because four rounds of a
# biquad at 5.2 kHz is mud and this engine has shipped a compounding-lowpass bug
# before.
def sonitex_filters(p, last:)
  [
    "acompressor=threshold=#{p[:comp_threshold]}dB:ratio=#{p[:comp_ratio]}:" \
      "attack=#{p[:comp_attack]}:release=#{p[:comp_release]}:makeup=#{p[:comp_makeup]}",
    "stereotools=slev=#{(p[:stereo_width] * p[:side_gain]).round(3)}",
    "equalizer=f=#{p[:dist_pre_lp]}:t=h:w=1:g=#{p[:dist_pre_emph_db]}",
    "asoftclip=type=tanh:param=#{p[:dist_drive]}",
    "equalizer=f=#{p[:dist_pre_lp]}:t=h:w=1:g=#{(-p[:dist_pre_emph_db] * 0.75).round(2)}",
    "lowpass=f=#{p[:hf_rolloff]}",
    "highpass=f=#{p[:lf_rolloff]}",
    "equalizer=f=#{p[:head_bump_hz]}:t=q:w=1.4:g=#{p[:head_bump_db]}",
    "vibrato=f=#{p[:wow_rate]}:d=#{p[:wow_depth]}",
    "vibrato=f=#{p[:flutter_hz]}:d=#{p[:flutter_depth]}",
    "equalizer=f=#{p[:sibilance_hz]}:t=h:w=1:g=#{p[:sibilance_db]}",
    "acrusher=bits=#{p[:crush_bits]}:mix=#{p[:crush_mix]}:samples=2",
    (last ? "lowpass=f=#{p[:groove_wear_lp]}" : nil),
    "acompressor=threshold=#{p[:out_comp_threshold]}dB:ratio=#{p[:out_comp_ratio]}:makeup=#{p[:out_comp_makeup]}",
    "alimiter=limit=#{p[:limit]}",
  ].compact
end

# Four console paths at sub-millisecond offsets. At these delays the copies land
# inside one wavelength of each other and comb rather than echo, which is the
# hollow a parallel console sum has and a single path does not.
NASTY_FILTER = "aecho=0.92:0.88:0.3|0.7|1.1:0.5|0.42|0.34"
DEEP_FILTERS = ["stereotools=delay=11",
                "aphaser=in_gain=0.6:out_gain=0.7:delay=3:decay=0.35:speed=0.12",
                "aecho=0.8:0.75:66|132:0.32|0.18"].freeze

def master_filter_chain
  @master_filter_chain ||= begin
    rounds = (ENV["SINE_MASTER_ROUNDS"] || "4").to_i.clamp(1, 8)
    parts = []
    rounds.times do |k|
      2.times { parts.concat(sonitex_filters(SONITEX_STX1260, last: false)) }
      parts.concat(sonitex_filters(SONITEX_STX1260, last: true))
      parts << NASTY_FILTER
      parts.concat(DEEP_FILTERS) if k == rounds - 1 && ENV["SINE_DEEP"] != "0"
    end
    parts << "acompressor=threshold=-12dB:ratio=2:attack=30:release=260:makeup=1.15"
    parts << "alimiter=limit=0.94"
    parts.join(",")
  end
end

def master_chain!(l, r)
  tmp_in = File.join(OUT, "master_in_#{Process.pid}.wav")
  tmp_out = File.join(OUT, "master_out_#{Process.pid}.wav")
  write_wav(tmp_in, l, r)
  ok = system("/opt/homebrew/bin/ffmpeg", "-y", "-i", tmp_in, "-af", master_filter_chain,
              "-c:a", "pcm_s16le", tmp_out, out: File::NULL, err: File::NULL)
  got = ok && File.file?(tmp_out) && File.size(tmp_out) > 1000 ? read_wav(tmp_out) : nil
  FileUtils.rm_f(tmp_in)
  FileUtils.rm_f(tmp_out)
  # If ffmpeg refused the graph the music still has to reach the speakers, so
  # fall back to the ceiling alone rather than to nothing.
  return soft_limit!(l, r, ceiling: 0.94) unless got

  n = [l.length, got[0].length].min
  n.times { |i| l[i] = got[0][i]; r[i] = got[1][i] }
  (n...l.length).each { |i| l[i] = 0.0; r[i] = 0.0 }
end


# The vocal chain, which is not the pad chain.
#
# Modulation and spatial movement are for the pad. A rapper through a phaser or
# a ring modulator is an effect on a voice, and the voice is here to complete the
# music rather than to be processed by it -- so this is the small set that makes
# a vocal sit: roll off what is below the voice, hold the level, lift the
# presence so consonants read, and one short slap for depth. Nothing that moves.
def vocal_chain!(l, r)
  n = l.length
  # High pass at roughly 110 Hz -- below the voice, above nothing worth keeping.
  k = 1.0 - Math.exp(-2 * Math::PI * 110.0 / RATE)
  hl = 0.0
  hr = 0.0
  n.times do |i|
    hl += k * (l[i] - hl)
    hr += k * (r[i] - hr)
    l[i] -= hl
    r[i] -= hr
  end
  compress!(l, r, threshold_db: -20, ratio: 3.2, attack_ms: 8, release_ms: 120, makeup: 1.25)
  # Presence: add back the band above ~2.4 kHz so words stay legible under a
  # pad that is deliberately mid-heavy.
  kp = 1.0 - Math.exp(-2 * Math::PI * 2400.0 / RATE)
  pl = 0.0
  pr = 0.0
  n.times do |i|
    pl += kp * (l[i] - pl)
    pr += kp * (r[i] - pr)
    l[i] += (l[i] - pl) * 0.35
    r[i] += (r[i] - pr) * 0.35
  end
  # One slap, 84 ms, quiet -- depth without smearing the timing.
  d = (RATE * 0.084).to_i
  n.times do |i|
    next if i < d

    l[i] += r[i - d] * 0.14
    r[i] += l[i - d] * 0.11
  end
end

# Artifacts. The things a clean chain is built to prevent.
#
# Each of these is a failure mode of real equipment -- a fold in an overdriven
# stage, a tape dropout, a sampler repeating its buffer, a converter losing bits.
# Applied to the music bus only: the vocal is summed after the master chain and
# never sees any of it.

# Wavefolding. wav_Map reads an image as a height field and the wavetable it
# builds folds back on itself where the picture does; this is that fold without
# the picture. Past unity the waveform turns back instead of clipping, which adds
# high harmonics that are not the ones distortion adds.
def wave_fold!(l, r, amount: 1.9, mix: 0.5)
  l.length.times do |i|
    l[i] = l[i] * (1 - mix) + fold_once(l[i] * amount) * mix
    r[i] = r[i] * (1 - mix) + fold_once(r[i] * amount) * mix
  end
end

# Closed form, not a loop.
#
# The first version subtracted a multiple of four while the sample was out of
# range, and at x = 2.0 that multiple is zero -- so it subtracted nothing and
# spun forever. artifacts! calls this on every progression, which is why the
# generator sat at a hundred percent CPU and never wrote a file: not memory, not
# scheduling, one unbounded while.
#
# A wavefolder is a triangle wave of its input, so say that instead: reflect
# through 1 and -1 as many times as the arithmetic implies, in one step.
def fold_once(x)
  1.0 - ((x + 1.0) % 4.0 - 2.0).abs
end

# The sampler catching on its own buffer. A slice is held and repeated, and the
# repeats shorten -- which is the gesture, not the repetition itself.
def stutter!(l, r, seed: 3, events: 4, mix: 1.0)
  n = l.length
  rnd = Random.new(seed)
  events.times do
    at = (rnd.rand * (n * 0.85)).to_i
    len = (RATE * (0.03 + rnd.rand * 0.09)).to_i
    next if at + len * 6 >= n

    reps = 3 + rnd.rand(4)
    cur = len
    pos = at + len
    reps.times do
      break if pos + cur >= n

      cur.times do |k|
        w = 0.5 - 0.5 * Math.cos(2 * Math::PI * k / cur)
        l[pos + k] = l[pos + k] * (1 - mix * w) + l[at + k] * mix * w
        r[pos + k] = r[pos + k] * (1 - mix * w) + r[at + k] * mix * w
      end
      pos += cur
      cur = (cur * 0.72).to_i
      break if cur < 200
    end
  end
end

# Grains played backwards in place. Short enough that the music keeps its shape
# and the ear reads it as a smear rather than as a reversal.
def reverse_grains!(l, r, seed: 5, count: 6, grain_ms: 140.0)
  n = l.length
  g = (RATE * grain_ms / 1000.0).to_i
  return if g < 64 || n < g * 3

  rnd = Random.new(seed)
  count.times do
    at = (rnd.rand * (n - g - 1)).to_i
    sl = l[at, g].reverse
    sr = r[at, g].reverse
    g.times do |k|
      w = 0.5 - 0.5 * Math.cos(2 * Math::PI * k / g)
      l[at + k] = l[at + k] * (1 - w) + sl[k] * w
      r[at + k] = r[at + k] * (1 - w) + sr[k] * w
    end
  end
end

# Tape dropouts. Oxide missing from the tape: the level falls and the top goes
# with it, over a few milliseconds rather than instantly.
def dropouts!(l, r, seed: 7, count: 5)
  n = l.length
  rnd = Random.new(seed)
  count.times do
    at = (rnd.rand * n).to_i
    len = (RATE * (0.02 + rnd.rand * 0.10)).to_i
    next if at + len >= n

    z = 0.0
    len.times do |k|
      t = k.to_f / len
      duck = 1.0 - 0.85 * Math.sin(Math::PI * t)
      z += 0.05 * (l[at + k] - z)
      l[at + k] = (l[at + k] * 0.4 + z * 0.6) * duck
      r[at + k] *= duck
    end
  end
end

# Bits gone. Not a smooth quantiser -- the low bits are dropped outright, which
# is what a converter losing its footing actually sounds like.
def bit_mangle!(l, r, bits: 7, mix: 0.35)
  q = 2**(bits - 1)
  l.length.times do |i|
    ml = (l[i] * q).to_i.to_f / q
    mr = (r[i] * q).to_i.to_f / q
    l[i] = l[i] * (1 - mix) + ml * mix
    r[i] = r[i] * (1 - mix) + mr * mix
  end
end

# Two or three of them per progression, chosen by seed so a take is reproducible
# and no two neighbours get the same set.
ARTIFACTS = %i[fold stutter reverse dropout bits].freeze

def artifacts!(l, r, seed:, count: 2)
  rnd = Random.new(seed)
  ARTIFACTS.shuffle(random: rnd).first(count).each do |k|
    case k
    when :fold then wave_fold!(l, r, amount: 1.5 + rnd.rand, mix: 0.3 + rnd.rand * 0.3)
    when :stutter then stutter!(l, r, seed: seed + 1, events: 2 + rnd.rand(4))
    when :reverse then reverse_grains!(l, r, seed: seed + 2, count: 3 + rnd.rand(6))
    when :dropout then dropouts!(l, r, seed: seed + 3, count: 3 + rnd.rand(5))
    when :bits then bit_mangle!(l, r, bits: 6 + rnd.rand(3), mix: 0.25 + rnd.rand * 0.25)
    end
  end
end

# Old takes as source, rather than as rubbish.
#
# A previous render that does not work as a record still contains a performance,
# and the way this engine has always treated a performance it did not make is to
# sample it. Deleting a take because it sounds amateur throws away the one thing
# that cannot be regenerated: a decision somebody made at a particular moment.
#
# So: strip the top off it, which removes the hats and cymbals and with them most
# of what dates a beat; keep the body, which is the harmony and the room; run it
# through Copy Machine so it stops being a loop and becomes a cloud of itself;
# and put the current kit over it. What comes out is the old take's harmony under
# new drums, which is the Detroit method pointed at our own back catalogue.
RECYCLE_DIRS = [
  "/Users/mac/Documents/GitHub/pub4/STUDIO/dilla/scratch/all_tracks_demo",
  "/Users/mac/Music/dilla_showcase/queue",
].freeze

def recycle_sources
  @recycle_sources ||= RECYCLE_DIRS.flat_map { |d| Dir[File.join(d, "*.wav")] }
                                   .reject { |x| x.include?("_stems/") }
                                   .select { |x| File.size(x) > 400_000 }
                                   .sort
end

# Everything above ~2.2 kHz goes, two poles of it. That is where the hats live,
# and a beat is mostly identifiable by its hats.
def strip_top!(l, r, hz: 2200.0)
  k = (1.0 - Math.exp(-2 * Math::PI * hz / RATE)).clamp(0.0005, 0.99)
  2.times do
    zl = 0.0
    zr = 0.0
    l.length.times do |i|
      zl += k * (l[i] - zl)
      zr += k * (r[i] - zr)
      l[i] = zl
      r[i] = zr
    end
  end
end

def recycle_bed!(l, r, index, gain: 0.34)
  srcs = recycle_sources
  return false if srcs.empty?

  got = read_wav(srcs[index % srcs.length])
  return false unless got

  bl, br, = got
  n = l.length
  return false if bl.length < n / 2

  # Start somewhere other than the top of the file, so the same source used
  # twice does not give the same bar twice.
  off = (index * 97_003) % [bl.length - 1, 1].max
  seg_l = Array.new(n) { |i| bl[(off + i) % bl.length] }
  seg_r = Array.new(n) { |i| br[(off + i) % br.length] }
  strip_top!(seg_l, seg_r)
  copy_machine!(seg_l, seg_r, copies: 3, reverse: 0.3, width: 0.9)
  n.times do |i|
    l[i] += seg_l[i] * gain
    r[i] += seg_r[i] * gain
  end
  true
end

# Two-operator FM, with the carrier morphing between triangle and square.
#
# The soundfont stacks give warmth and they cannot give this: FM sidebands are
# inharmonic when the ratio is not a whole number, and no amount of filtering a
# sampled Rhodes produces them. The modulation index falls over the note, which
# is the DX7 electric-piano gesture -- bright at the strike, pure by the tail.
#
# The carrier is not a sine. tanh(k*sin) approaches a square as k rises and
# 2/pi*asin(sin) is a triangle, and morphing between them under an LFO is the
# waveform itself moving rather than a filter moving over it.
def morph_wave(phase, morph, hard)
  tri = 2.0 / Math::PI * Math.asin(Math.sin(phase).clamp(-1.0, 1.0))
  sq = Math.tanh(Math.sin(phase) * hard)
  tri * (1.0 - morph) + sq * morph
end

def fm_chord!(l, r, hzs, bass_hz, secs, seed: 0, gain: 0.5)
  n = [(RATE * secs).to_i, l.length].min
  voices = hzs.map(&:to_f).reject { |h| h <= 0 }.sort
  voices = voices + [bass_hz.to_f] if bass_hz.to_f > 0
  return if voices.empty?

  rnd = Random.new(seed)
  # Ratios that are not whole numbers on purpose: 2.01 and 3.5 give sidebands
  # that do not land on the harmonic series, which is the FM sound.
  ratios = [1.0, 2.01, 3.5, 1.414, 7.0]
  amp = gain / Math.sqrt(voices.length)
  morph_rate = 2 * Math::PI * (0.06 + rnd.rand * 0.09) / RATE
  voices.each_with_index do |hz, vi|
    ratio = ratios[(vi + seed) % ratios.length]
    idx0 = 2.4 + rnd.rand * 3.6
    pan = voices.length > 1 ? ((vi.to_f / (voices.length - 1)) - 0.5) * 0.8 : 0.0
    lg = Math.cos((pan + 1) * Math::PI / 4)
    rg = Math.sin((pan + 1) * Math::PI / 4)
    wc = 2 * Math::PI * hz / RATE
    wm = wc * ratio
    pc = 0.0
    pm = 0.0
    n.times do |i|
      t = i.to_f / n
      index = idx0 * Math.exp(-t * 2.6)
      pm += wm
      pc += wc
      morph = 0.5 + 0.5 * Math.sin(morph_rate * i + vi)
      v = morph_wave(pc + index * Math.sin(pm), morph, 3.4 + morph * 6.0)
      env = Math.exp(-t * 1.5) * [i / (RATE * 0.006), 1.0].min
      l[i] += v * amp * env * lg
      r[i] += v * amp * env * rg
    end
  end
end

# The shape of the stream, assessed from outside it.
#
# Every take was the same length, the same density and the same crossfade. That
# is a canal: constant width, constant flow, no reason for anything to happen at
# any particular moment. A river is not uniform -- it pools and it quickens, it
# narrows into rapids and opens out again, and the transitions between those are
# where it is worth listening.
#
# So the stream now moves on a slow cycle roughly sixteen progressions long.
# Near the low point the takes are short and almost unprocessed: harmony, kit,
# and little else. Near the high point they are long, layered and heavily
# treated. Nothing announces the change; the width just varies, which is how a
# river reads as alive rather than as a channel.
FLOW_PERIOD = (ENV["SINE_FLOW_PERIOD"] || "16").to_f

def flow_at(slot)
  # Two cycles of different lengths, so the shape does not repeat on a bar line.
  a = Math.sin(2 * Math::PI * slot / FLOW_PERIOD)
  b = Math.sin(2 * Math::PI * slot / (FLOW_PERIOD * 2.6) + 1.1)
  ((a * 0.65 + b * 0.35) + 1.0) / 2.0
end

def flow_shape(slot)
  d = flow_at(slot)
  {
    depth: d,
    # Pools hold two chords; rapids run six.
    chords: (2 + (d * 4).round).clamp(2, 6),
    # Calm stretches get no artifacts at all. A river is not turbulent
    # everywhere, and constant turbulence reads as noise rather than as motion.
    artifacts: d < 0.34 ? 0 : (d < 0.7 ? 1 : 3),
    # Wider crossfades in the slow parts, so the pools run into each other, and
    # tighter ones in the fast parts where the edges should be audible.
    xfade: (RATE * (2.2 - d * 1.7)).to_i,
    # The recycled bed belongs in the deep water.
    recycle: d > 0.62,
    # The FM layer is the quickening.
    fm: d > 0.45,
  }
end

def master_pass!(l, r)
  # Three Sonitex passes, the third on the extreme parameter set. Stacking the
  # same lo-fi chain is not the same as turning one up: each pass band-limits
  # what the previous one distorted, so the grit compounds while the bandwidth
  # keeps closing.
  passes = (ENV["SINE_SONITEX_PASSES"] || "3").to_i
  (passes - 1).times { sonitex_pass!(l, r, SONITEX_STX1260, amount: 1.0) }
  sonitex_pass!(l, r, defined?(SONITEX_STX1269) ? SONITEX_STX1269 : SONITEX_STX1260, amount: 0.8)

  nasty_vcs_sum!(l, r, instances: (ENV["SINE_NASTY_INSTANCES"] || "4").to_i)

  unless ENV["SINE_DEEP"] == "0"
    haas_spread!(l, r, ms: 11.0, mix: 0.42)
    resonant_sweep!(l, r)
    master_dub!(l, r)
  end

  # Standard tools last: a slow bus compressor, then the ceiling.
  compress!(l, r, threshold_db: -12, ratio: 2.0, attack_ms: 30, release_ms: 260, makeup: 1.15)
  soft_limit!(l, r, ceiling: 0.94)
end

# The preset's ROLE, as an oscillator rather than as an equaliser.
#
# Applying a preset's EQ curve to a sine leaves a sine -- correctly filtered and
# still unmistakably one waveform, which is why a rotation through 54 presets
# sounded like one pad. The role is the part that changes the instrument: an
# electric piano is a struck tine with odd partials that decay faster than the
# fundamental, a pad is a slow swell with few partials, a texture is detuned and
# noisy. Those are different oscillators, and that is what is audible.
ROLE_VOICE = {
  ep:         { partials: [[1, 1.0, 1.0], [2, 0.42, 2.2], [3, 0.26, 3.1], [5, 0.11, 4.4], [9, 0.05, 6.0]],
                attack: 0.004, decay: 2.6 },
  warm:       { partials: [[1, 1.0, 1.0], [2, 0.20, 1.2], [3, 0.08, 1.5]],
                attack: 0.42, decay: 0.15 },
  lead:       { partials: [[1, 1.0, 1.0], [2, 0.34, 1.1], [3, 0.30, 1.2], [4, 0.16, 1.4], [5, 0.12, 1.6]],
                attack: 0.06, decay: 0.5 },
  texture:    { partials: [[1, 1.0, 1.0], [2, 0.18, 0.9], [3, 0.22, 1.1], [7, 0.14, 1.3]],
                attack: 0.30, decay: 0.3, detune: 11.0 },
  bass:       { partials: [[0.5, 0.9, 1.0], [1, 1.0, 1.2], [3, 0.18, 2.0]],
                attack: 0.01, decay: 1.4 },
  native:     { partials: [[1, 1.0, 1.0], [3, 0.24, 1.6], [5, 0.13, 2.2]],
                attack: 0.08, decay: 0.9 },
  scale_lead: { partials: [[1, 1.0, 1.0], [2, 0.28, 1.3], [4, 0.14, 1.8]],
                attack: 0.05, decay: 0.7 },
}.freeze

def role_voice(preset)
  ROLE_VOICE[preset && preset[:role]] || ROLE_VOICE[:warm]
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
def add_voice!(left, right, hz, amp, pan, n, treat, vi, total, entry = 0, shape = nil)
  return if hz <= 0

  lg = Math.cos((pan + 1) * Math::PI / 4)
  rg = Math.sin((pan + 1) * Math::PI / 4)
  base = 2 * Math::PI * (hz * PITCH) / RATE

  # Detunes: a single sine is inert, two a few cents apart beat against each
  # other, and beating is what makes a pure tone sound alive rather than tested.
  role_detune = (shape && shape[:detune]) || 0.0
  detunes = case treat
            when :shimmer then [0.0, 5.0, -7.0]
            when :bloom then [0.0, 3.0]
            else role_detune.positive? ? [0.0, role_detune, -role_detune] : [0.0]
            end
  detunes.each do |cents|
    step = base * (2.0**(cents / 1200.0))
    ph = 0.0
    va = amp / detunes.length
    trem_rate = 2 * Math::PI * (0.7 + vi * 0.13) / RATE
    drift_rate = 2 * Math::PI * (0.05 + vi * 0.017) / RATE
    shape ||= ROLE_VOICE[:warm]
    partials = if treat == :plaits
                 plaits_partials(0.35 + (vi.to_f / [total, 1].max) * 0.6).map { |m, w| [m, w, 1.0] }
               else
                 shape[:partials]
               end
    pnorm = partials.sum { |(_, w, _)| w }
    atk = [(shape[:attack] * RATE).to_i, 1].max
    dec = shape[:decay].to_f
    n.times do |i|
      next if i < entry
      t = (i - entry).to_f / n
      s = partials.sum { |(mult, w, dk)| Math.sin(ph * mult) * w * Math.exp(-t * dec * dk) } / pnorm
      s *= [(i - entry).to_f / atk, 1.0].min
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

def chord_samples(hzs, bass_hz, secs, treat, preset = nil)
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
    add_voice!(left, right, hz, amp * w, pan, n, treat, vi, all.length, entry, role_voice(preset))
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

# All eleven pad stacks, walked in order. The warm classics and the odd ones get
# the same amount of airtime; picking only the safe ones is how a synth engine
# ends up sounding like one synth.
PAD_STACKS = PAD_LAYER_STACKS.keys.freeze

# The analog drum bus ships at zero. WONKY_TOP_DIRT and WONKY_HAT_DUCK are both
# `ENV[...] || 0` in lib/engine/drum_bus.rb, so the dual-bus split, the top-end
# dirt and the kick-triggered hat duck are all built, all documented, and all
# silent unless something asks for them. This asks.
ENV["WONKY_TOP_DIRT"] ||= "0.42"
ENV["WONKY_HAT_DUCK"] ||= "0.55"
ENV["DRUM_FIELD_MIX"] ||= "0.18"

cfg = dilla_resolve_config
names = CHORD_PROGRESSIONS.keys
xf = (RATE * XFADE).to_i
# The cursor survives a restart. Without it the generator began the catalogue at
# index 0 every time it came back, so the first six progressions were regenerated
# over and over and the stream sounded like it had stopped rotating -- which,
# from the listener's side, it had.
# A salt that advances on every start. Without it a restart re-shuffled to the
# same order, which from the speakers is indistinguishable from not shuffling.
SALT_FILE = File.join(OUT, "salt.txt")
SALT = ((File.file?(SALT_FILE) ? File.read(SALT_FILE).to_i : 0) + 1).tap { |v| File.write(SALT_FILE, v.to_s) }
CURSOR = File.join(OUT, "cursor.txt")
saved = File.file?(CURSOR) ? File.read(CURSOR).split.map(&:to_i) : [1, 0, 0]
round = saved[0] - 1
start_group = saved[1]
seq = saved[2]

loop do
  round += 1
  # Reordered every pass so a long listen is not the same sequence twice.
  order = names.shuffle(random: Random.new(SALT + round * 7919))
  order.each_slice(PER_FILE).with_index do |group, gi|
    next if gi < start_group
    break if File.exist?(STOP)

    l = []
    r = []
    voc_l = []
    voc_r = []
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

      treat = TREATMENTS[((gi * PER_FILE + ni) * 7 + SALT * 5) % TREATMENTS.length]
      played << "#{name}/#{treat}~#{(flow_at(gi * PER_FILE + ni) * 100).round}"
      # The pads come from the engine's own synths, not from an oscillator in
      # this file. render_pad_via_fluidsynth plays the chord through a stack of
      # real SF2 instruments -- Rhodes, Prophet, CS-80, Solina, Juno -- with each
      # patch's own ffmpeg chain after it. A sine with the patch's EQ on it is
      # still a sine, which is why rotating 54 presets sounded like one pad.
      #
      # PAD_VOICE names the stack, and the rotation walks all eleven so a long
      # listen passes through the warm classics and the strange ones both.
      slot = gi * PER_FILE + ni
      stack = PAD_STACKS[(slot * 3 + SALT) % PAD_STACKS.length]
      ENV["PAD_VOICE"] = stack.to_s
      # Four chords per progression, not the whole thing: the point of the stream
      # is passing through the catalogue, and a ten-chord progression holds one
      # place for forty-six seconds.
      flow = flow_shape(gi * PER_FILE + ni)
      pads = pads.first(flow[:chords]) if pads.length > flow[:chords]
      xf = flow[:xfade]
      events = pads.each_with_index.map { |c, bi| [bi * SECS, 0.85, c, SECS * 1.02] }
      dur = pads.length * SECS
      tmp = File.join(OUT, "pad_#{gi}_#{ni}.wav")
      pl = []
      pr = []
      begin
        render_pad_via_fluidsynth(tmp, events, dur)
        got = File.file?(tmp) ? read_wav(tmp) : nil
        pl, pr = got[0], got[1] if got
      rescue StandardError => err
        warn "pad render failed for #{name}: #{err.class}"
      ensure
        FileUtils.rm_f(tmp)
      end
      # Fall back to the internal oscillator only if the synth path gave nothing,
      # so a missing soundfont degrades to sound rather than to silence.
      if pl.empty?
        pads.each_with_index do |c, bar|
          cl, cr = chord_samples(Array(c[:hz]), c[:bass_hz], SECS, treat, nil)
          crossfade_append!(pl, pr, cl, cr, xf)
        end
        played[-1] = "#{played.last}(osc)"
      else
        played[-1] = "#{played.last}[#{stack}]"
      end
      unless ENV["SINE_DRUMS"] == "0"
        pads.each_index { |bar| drums_for_bar!(pl, pr, (bar * SECS * RATE).to_i, SECS, bar) }
      end
      case treat
      when :copymachine then copy_machine!(pl, pr, copies: 4)
      when :cloud then copy_machine!(pl, pr, copies: 6, reverse: 0.45, width: 1.0)
      when :lpg then lpg!(pl, pr)
      when :echo then space_echo!(pl, pr, time_s: SECS / 6.0, feedback: 0.58)
      when :dub then space_echo!(pl, pr, time_s: SECS / 3.0, feedback: 0.72, heads: 4, mix: 0.6)
      when :ringmod then ring_mod!(pl, pr)
      when :chainsaw then comb_resonator!(pl, pr)
      when :barber then barber_phaser!(pl, pr)
      when :grains then granular_smear!(pl, pr, seed: gi * 31 + ni)
      when :machine
        # All four at once: mechanical on the surface, never twice the same underneath.
        ring_mod!(pl, pr, mix: 0.3)
        comb_resonator!(pl, pr, mix: 0.3)
        barber_phaser!(pl, pr, mix: 0.45)
        granular_smear!(pl, pr, mix: 0.35, seed: gi * 17 + ni)
      end
      # The vocal is kept on its own bus for the whole file and summed in AFTER
      # the master chain. Dirty is for the drums, the pads and the leads; four
      # passes of Sonitex through a cassette is exactly what a rapper should not
      # be going through. Same length as the music so the two stay aligned.
      unless ENV["SINE_VOCALS"] == "0" || pl.empty?
        slug = ni == group.length - 1 ? VOCAL_TAIL : VOCAL_LEAD
        seg_l = Array.new(pl.length, 0.0)
        seg_r = Array.new(pr.length, 0.0)
        if add_vocal!(seg_l, seg_r, slug, VOCAL_SPEED[slug], gi * PER_FILE + ni, gain: 1.0)
          vocal_chain!(seg_l, seg_r)
          played[-1] = "#{played.last}+#{slug}"
        end
        # Aligned to where this progression lands in the file, allowing for the
        # crossfade overlap that shortens every join.
        at = [l.length - xf, 0].max
        need = at + seg_l.length
        (voc_l.length...need).each { voc_l << 0.0; voc_r << 0.0 }
        seg_l.each_index { |i| voc_l[at + i] += seg_l[i]; voc_r[at + i] += seg_r[i] }
      end
      # An FM layer over the sampled stack on every other progression: sidebands
      # the soundfonts cannot make, with the carrier morphing triangle to square.
      if ENV["SINE_FM"] != "0" && flow[:fm]
        pads.each_with_index do |c, bar|
          at = (bar * SECS * RATE).to_i
          seg = pl.length - at
          next if seg < 1000

          tl = Array.new(seg, 0.0)
          tr = Array.new(seg, 0.0)
          fm_chord!(tl, tr, Array(c[:hz]), c[:bass_hz], SECS, seed: bar + ni, gain: 0.42)
          seg.times { |i| pl[at + i] += tl[i]; pr[at + i] += tr[i] }
        end
        played[-1] = played.last + "+fm"
      end
      # Every third progression carries an old take underneath it.
      if ENV["SINE_RECYCLE"] != "0" && flow[:recycle] &&
         recycle_bed!(pl, pr, gi * PER_FILE + ni)
        played[-1] = played.last + "+recycled"
      end
      # The white water. Where the river runs fastest every device is on at
      # once -- the Copy Machine cloud, the Space Echo, the ring modulator, the
      # comb and the folder -- each at a fraction of the mix it would take on
      # its own, because five devices at full strength is not a flurry, it is
      # mud. Only above 0.85, so it stays an event rather than a texture.
      if flow[:depth] > 0.85 && ENV["SINE_FLURRY"] != "0"
        copy_machine!(pl, pr, copies: 5, reverse: 0.4, width: 1.0)
        space_echo!(pl, pr, time_s: SECS / 5.0, feedback: 0.5, heads: 3, mix: 0.3)
        ring_mod!(pl, pr, hz: 61.0, drift_hz: 0.23, mix: 0.18)
        comb_resonator!(pl, pr, hz_from: 210.0, hz_to: 88.0, feedback: 0.55, mix: 0.22)
        wave_fold!(pl, pr, amount: 1.6, mix: 0.22)
        played[-1] = played.last + "+flurry"
      end
      # Artifacts on the music bus, before the phase movement so the movement
      # carries them across the field rather than sitting them in the middle.
      artifacts!(pl, pr, seed: gi * 101 + ni, count: flow[:artifacts]) if flow[:artifacts].positive? && ENV["SINE_ARTIFACTS"] != "0"
      # A slow phase movement on every pad regardless of treatment -- a static
      # stereo image is what makes a long stream stop sounding alive.
      barber_phaser!(pl, pr, rate_hz: 0.04 + flow[:depth] * 0.09,
                     depth: 0.35 + flow[:depth] * 0.4, mix: 0.14 + flow[:depth] * 0.26)
      cassette!(pl, pr) unless ENV["SINE_CASSETTE"] == "0"
      crossfade_append!(l, r, pl, pr, xf)
    end
    next if l.empty?

    # Top and tail so the file itself does not click in or out.
    edge = (RATE * 0.05).to_i
    edge.times do |i|
      g = i.to_f / edge
      l[i] *= g; r[i] *= g
      l[-1 - i] *= g; r[-1 - i] *= g
    end

    master_chain!(l, r)
    # The voice, clean, over the mastered music. Under it on purpose -- this is a
    # record about the harmony, and the vocal completes it rather than fronts it.
    unless voc_l.empty?
      g = (ENV["SINE_VOCAL_GAIN"] || "0.26").to_f
      n = [l.length, voc_l.length].min
      n.times { |i| l[i] += voc_l[i] * g; r[i] += voc_r[i] * g }
      soft_limit!(l, r, ceiling: 0.94)
    end
    q = File.join(OUT, "q")
    # Stay a few files ahead and no further: enough that the player never
    # catches up, few enough that an edit to this file is heard soon.
    sleep 2 while Dir[File.join(q, "*.wav")].length >= 3 && !File.exist?(STOP)
    break if File.exist?(STOP)

    seq += 1
    tmp = File.join(q, format(".%06d.wav", seq))
    wav = File.join(q, format("%06d.wav", seq))
    write_wav(tmp, l, r)
    File.rename(tmp, wav) # atomic: the player never sees a half-written file
    File.write(CURSOR, "#{round} #{gi + 1} #{seq}")
    File.write(File.join(q, format("%06d.txt", seq)), "pass #{round}  #{played.join('  ->  ')}\n")
  end
  start_group = 0
  break if File.exist?(STOP)
end

