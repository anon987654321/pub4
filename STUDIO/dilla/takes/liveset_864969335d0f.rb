# MASTER's main sound, improvising: the frozen default (default_sound.rb),
# with the chords chosen live instead of looped. It opens on the loved
# progression, then walks soul-jazz harmony, each chord voiced nearest the
# last, a new moog patch every two chords, the DFAM on top. Endless.
$LOAD_PATH.unshift File.expand_path("~/Documents/GitHub/pub4/STUDIO/dilla/lib")
require "sound"

RATE = 32_000
BLOCK = 1_024
S = AnalogSynth
P = S::PATCHES.dup

def hz(midi) = 440.0 * (2.0**((midi - 69) / 12.0))

# Fm9, Bbm9, Eb13, Abmaj9, Dbmaj7#11, C7alt: soul-jazz, Dilla territory.
CHORDS = [
  [41, [56, 60, 63, 67]], [46, [56, 61, 65, 68]], [39, [55, 60, 61, 65]],
  [44, [55, 60, 63, 70]], [37, [60, 65, 67, 72]], [36, [58, 61, 64, 68]],
]
SNAP = { amp: S::Envelope.new(attack: 0.004, decay: 0.3, sustain: 0.35, release: 0.18),
         filter_env: S::Envelope.new(attack: 0.002, decay: 0.22, sustain: 0.2, release: 0.15) }.freeze
PROPHET_LEADS = {
  prophet_five_lead: P[:prophet_five].merge(SNAP),
  prophet_pad_lead: P[:prophet_pad].merge(SNAP),
  prophet_poly: P[:poly_lead].merge(SNAP),
  prophet_bright: P[:prophet_five].merge(SNAP).merge(cutoff: 900.0, resonance: 0.42),
}.freeze
P.merge!(PROPHET_LEADS)
PADS = %i[warm_pad poly_strings prophet_five juno_pad prophet_pad vp330_ensemble soft_reed e_piano rhodes_tine glass_bell]
BASSES = %i[moog_bass acid sub dub_bass]
QUALITIES = {
  m9: [3, 7, 10, 14], m11: [3, 7, 10, 17], maj9: [4, 7, 11, 14], maj7s11: [4, 7, 11, 18],
  d13: [4, 10, 14, 21], alt: [4, 10, 13, 15], m6_9: [3, 7, 9, 14], sus13: [5, 10, 14, 21],
}.freeze
MOVES = {
  [0, :m9] => [[5, :m9], [10, :d13], [8, :maj9], [5, :m11], [3, :maj9]],
  [0, :m11] => [[5, :m9], [8, :maj7s11], [10, :sus13]],
  [5, :m9] => [[10, :d13], [7, :alt], [3, :maj9], [0, :m6_9]],
  [5, :m11] => [[10, :d13], [7, :alt]],
  [10, :d13] => [[3, :maj9], [8, :maj9], [0, :m9]],
  [10, :sus13] => [[10, :d13], [3, :maj9]],
  [3, :maj9] => [[8, :maj9], [5, :m9], [1, :maj7s11]],
  [8, :maj9] => [[1, :maj7s11], [7, :alt], [5, :m9]],
  [8, :maj7s11] => [[7, :alt], [1, :maj7s11]],
  [1, :maj7s11] => [[7, :alt], [0, :m9], [0, :m11]],
  [7, :alt] => [[0, :m9], [0, :m11], [8, :maj9]],
  [0, :m6_9] => [[5, :m9], [10, :d13]],
}.freeze
NAMES = %w[C Db D Eb E F Gb G Ab A Bb B].freeze

def voice_lead(pcs, previous)
  pcs.each_with_index.map do |pc, idx|
    centre = previous[idx] || previous.last
    (53..74).select { |m| m % 12 == pc }.min_by { |m| (m - centre).abs }
  end.sort.uniq
end
BAR = 3.9
LOOPS = (ARGV[0] || 2).to_i

Voice = Struct.new(:hz, :spec, :start, :held, :gain, :phases, :ladder, :bass)

def voice(midi, spec, start, held, gain, bass: false)
  rng = Random.new(midi * 7 + (start * 10).to_i)
  Voice.new(hz(midi) * 2.0**(rng.rand(-0.7..0.7) / 1200.0), spec, start, held, gain,
            spec[:waves].map { rng.rand }, S::Ladder.new(rate: RATE), bass)
end

voices = []
rng = Random.new
key = 5 # F minor, where the loved progression sits
state = [0, :m9]
voicing = CHORDS.first.last
chord_i = 0
recent = []
next_modulation = 8
key = rng.rand(12)
next_chord = 0.0
LOG = File.open(File.join(__dir__, "moog_improv.log"), "a").tap { |f| f.sync = true }
total = Float::INFINITY

# The knobs: cutoff breathes over 23 s, resonance over 31 s, out of phase.
def cutoff_knob(t) = 0.55 + 0.45 * Math.sin(2 * Math::PI * t / 23.0)
def res_knob(t) = 0.5 + 0.5 * Math.sin(2 * Math::PI * t / 31.0 + 1.3)

# The DFAM, as the Moog is built: an 8-step sequencer, each step its own pitch
# and velocity, running in sixteenths; VCO 1 a triangle frequency-modulating
# VCO 2, a square; both with a pitch envelope that falls; noise mixed in; all
# of it through a ladder low-pass with its own decay, then the VCA's decay.
# The pattern starts from dilla's DfamEngine and one step mutates every two
# bars; decay and cutoff drift slowly, like the pads' knobs.
DFAM_STEP = BAR / 24
DFAM_LEVEL = 0.34
pattern = { pitch: [50, 30, 60, 20, 55, 35, 65, 25], velocity: [80, 60, 90, 50, 85, 65, 95, 55] }
dfam_rng = Random.new
dfam_hits = []
dfam_next = 0.0
dfam_step = 0
pattern_b = { pitch: [78, 64, 88, 70, 92], velocity: [55, 0, 70, 45, 60] }
# Accents on the eight-step page: the downbeat and the and-of-two lean in.
ACCENT = [1.35, 0.8, 1.0, 0.85, 1.25, 0.8, 1.1, 0.9].freeze
KICK_LEVEL = 0.09
# The lead plays over every chord, at the operator's word.
LEAD_ALWAYS = true
kicks = []
click_lp = 0.0
DfamHit = Struct.new(:start, :f0, :vel, :ph1, :ph2, :ladder, :pan)
class DfamKnob
  attr_reader :value

  def initialize(lo, hi, rng, speed:)
    @lo, @hi, @rng, @speed = lo, hi, rng, speed
    @x = 0.5
    @v = 0.0
    @push = nil
  end

  # A gesture: toward `target` (0..1) for `seconds`, then released.
  def lean(target, seconds, now) = @push = [target, now + seconds]

  def step(dt, now)
    @push = nil if @push && now > @push[1]
    pull = @push ? (@push[0] - @x) * 1.5 : (0.5 - @x) * 0.03
    @v = (@v * 0.992) + (@rng.rand(-1.0..1.0) * @speed * dt) + (pull * dt)
    @x = (@x + (@v * dt)).clamp(0.0, 1.0)
    @value = @lo + ((@hi - @lo) * @x)
  end
end

knob_rng = Random.new
DFAM_KNOBS = {
  vcf_decay: DfamKnob.new(0.03, 0.22, knob_rng, speed: 0.08),
  vca_decay: DfamKnob.new(0.06, 0.28, knob_rng, speed: 0.07),
  cutoff: DfamKnob.new(500.0, 4200.0, knob_rng, speed: 0.1),
  resonance: DfamKnob.new(0.2, 0.85, knob_rng, speed: 0.06),
  fm: DfamKnob.new(0.0, 1.1, knob_rng, speed: 0.07),
  noise: DfamKnob.new(0.02, 0.45, knob_rng, speed: 0.05),
  pitch_amount: DfamKnob.new(0.6, 4.0, knob_rng, speed: 0.06),
  pitch_decay: DfamKnob.new(0.015, 0.12, knob_rng, speed: 0.05),
}.freeze
next_gesture = 8.0

$stderr.puts "improvising: #{PADS.join(" -> ")} over moog_bass, DFAM on top"
def sonitex(bits:, lo:, hi:, drive:, mix: 0.5, samples: 1)
  "volume=#{drive},acrusher=bits=#{bits}:mode=log:aa=1:mix=#{mix}:samples=#{samples}," \
    "highpass=f=#{lo},lowpass=f=#{hi},alimiter=limit=0.99"
end

# Level-neutral here: five stages at livesets' -7.5 dB each sank the pads 37 dB
# under the kick. The colour stays; the loss does not.
def vcs(depth:, smear:, db: 0.0)
  phaser_db = -2.6 + (10.9 * (depth - 0.26)) - (0.14 * (smear - 2.1))
  "aphaser=in_gain=0.75:out_gain=0.85:delay=#{smear}:decay=#{depth}:speed=0.5," \
    "aecho=0.9:1:#{smear.round}:0.08,volume=#{(db - phaser_db + 0.65).round(2)}dB"
end

MASTER = [
  vcs(depth: 0.34, smear: 2.4), sonitex(bits: 12, lo: 40, hi: 13_000, drive: 1.12),
  vcs(depth: 0.38, smear: 1.7), sonitex(bits: 13, lo: 42, hi: 15_000, drive: 1.04),
  vcs(depth: 0.26, smear: 3.6), sonitex(bits: 11, lo: 42, hi: 12_000, drive: 1.18),
  "alimiter=limit=0.95"
].join(",")
def space_echo(head_ms, decays)
  taps = [1, 2, 3].map { |k| (head_ms * k).round }.join("|")
  "highpass=f=160,aecho=0.9:0.9:#{taps}:#{decays},lowpass=f=3200,chorus=0.9:0.9:25:0.35:0.6:1.8"
end
HEAD = BAR / 16 * 1000
ARP_FX = "afreqshift=shift=6:level=1,flanger=delay=3:depth=6:regen=35:speed=0.13:width=80,vibrato=f=4.8:d=0.18,acrusher=bits=9:mix=0.22:mode=log:aa=1,apulsator=hz=0.21:amount=0.7"
GRAPH = "[0:a]pan=stereo|c0=c0|c1=c1,#{MASTER}[m];[0:a]pan=stereo|c0=c2|c1=c3,#{ARP_FX}[a];[m][a]amix=inputs=2:weights=1 1:normalize=0,alimiter=limit=0.96"
sox = IO.popen(["sh", "-c", "ffmpeg -loglevel error -f s16le -ar #{RATE} -ac 4 -i - -filter_complex '#{GRAPH}' -f s16le -ar #{RATE} -ac 2 - | sox -q -t raw -r #{RATE} -e signed -b 16 -c 2 - -d"], "wb")
frame = 0
frames = Float::INFINITY
two_pi = 2 * Math::PI
while frame < frames
  # The next chord, chosen a second before it sounds.
  while next_chord < (frame.to_f / RATE) + 1.0
    degree, quality = state
    voicing = voice_lead(QUALITIES[quality].map { |iv| (key + degree + iv) % 12 }, voicing)
    bass = 36 + ((key + degree) % 12)
    bass += 12 if bass < 36
    name = "#{NAMES[(key + degree) % 12]}#{quality}"
    recent << [(key + degree) % 12, quality]
    recent.shift if recent.size > 4
    options = MOVES.fetch(state).reject { |d, q| recent.include?([(key + d) % 12, q]) }
    options = MOVES.fetch(state) if options.empty?
    state = options.sample(random: rng)
    roll = rng.rand
    if roll < 0.08 # the tritone substitute: a dominant a flat fifth away
      key = (key + 6) % 12
      name += " (tritone sub next)"
    elsif roll < 0.14 # a chromatic side-step, up or down a semitone
      key = (key + [1, 11].sample(random: rng)) % 12
      name += " (side-step next)"
    end
    if chord_i >= next_modulation
      key = (key + [5, 3, 8, 10, 2, 7].sample(random: rng)) % 12
      state = [0, %i[m9 m11 m6_9].sample(random: rng)]
      next_modulation = chord_i + rng.rand(8..16)
      name += " -> #{NAMES[key]} minor"
    end
    pad = P.fetch(PADS[chord_i % PADS.size])
    bass_patch = P.fetch(BASSES[(chord_i / 4) % BASSES.size])
    voicing.each { |m| voices << voice(m, pad, next_chord, BAR - 0.1, 0.22) }
    # Moog bass: the chord root twice a bar, the second a little late.
    voices << voice(bass, bass_patch, next_chord, 1.6, 0.55, bass: true)
    voices << voice(bass, bass_patch, next_chord + (BAR * 0.534), 1.2, 0.45, bass: true)
    LOG.puts "#{Time.now.strftime("%H:%M:%S")} #{name} on #{PADS[chord_i % PADS.size]}, bass #{BASSES[(chord_i / 4) % BASSES.size]}"
    if LEAD_ALWAYS || rng.rand < 0.3
ensemble = PROPHET_LEADS.keys.shuffle(random: rng)
pendulum = [0, 1, 2, 3, 2, 1]
bag = (voicing + voicing.map { |m| m + 12 }).sort.map { |m| m + 12 }
pick = rng.rand(bag.size)
step = BAR / 16
16.times do |k|
  next if pattern[:velocity][k % 8].zero? # the bag rests where the DFAM does

  pick = (pick + [-1, 1].sample(random: rng)).clamp(0, bag.size - 1)
  spec = P.fetch(ensemble[pendulum[k % pendulum.size]]).merge(lpg: 0.8)
  vel = pattern[:velocity][k % 8] / 100.0
  voices << voice(bag[pick], spec, next_chord + (k * step), step * 0.7, 0.28 * vel.clamp(0.5, 1.0), bass: :arp)
end
      LOG.puts "  arp: bag over the dfam rhythm, hocket across #{ensemble.join(" ")}"
    end
    chord_i += 1
    next_chord += BAR
  end
  n = BLOCK
  left = Array.new(n, 0.0)
  arp_l = Array.new(n, 0.0)
  arp_r = Array.new(n, 0.0)
  right = Array.new(n, 0.0)
  tb = frame.to_f / RATE
  ck = cutoff_knob(tb)
  rk = res_knob(tb)
  voices.each do |v|
    spec = v.spec
    rel = spec[:amp].release
    next if tb + (n.to_f / RATE) < v.start || tb > v.start + v.held + rel
    level = 1.0 / spec[:waves].size
    freqs = spec[:waves].each_index.map { |k| v.hz * (2.0**spec[:octaves][k]) * (2.0**(spec[:detune][k] / 1200.0)) }
    base_cut = spec[:cutoff] * (v.bass == true ? 0.7 + ck * 0.8 : 0.35 + ck * 1.6)
    res = v.bass == true ? spec[:resonance] : [spec[:resonance] + rk * 0.45, 0.85].min
    # The envelopes at control rate, every 16 samples: inaudible, and half the
    # cost that had the player at 100% of a core and dropping blocks.
    waves = spec[:waves]
    nw = waves.size
    out_l, out_r = v.bass == :arp ? [arp_l, arp_r] : [left, right]
    cut = ampv = 0.0
    j = 0
    while j < n
      t = tb + (j.to_f / RATE) - v.start
      if t >= 0
        if (j & 15).zero?
          shape = spec[:filter_env].at(t, v.held)
          shape = (shape * (1.0 - spec[:lpg])) + (spec[:amp].at(t, v.held) * spec[:lpg]) if spec[:lpg]
          cut = (base_cut + (spec[:env_amount] * shape)).clamp(30.0, 12_000.0)
          ampv = spec[:amp].at(t, v.held) * v.gain
        end
        raw = 0.0
        k = 0
        while k < nw
          v.phases[k] = (v.phases[k] + (freqs[k] / RATE)) % 1.0
          raw += S.wave(waves[k], v.phases[k]) * level
          k += 1
        end
        out = v.ladder.process(raw * spec[:drive], cut, res) * ampv
        out_l[j] += out * 0.52
        out_r[j] += out * 0.48
      end
      j += 1
    end
  end
voices.reject! { |v| tb > v.start + v.held + v.spec[:amp].release }

# Sequence the DFAM a block ahead.
while dfam_next < tb + (n.to_f / RATE)
  step = dfam_step % 8
  vel = pattern[:velocity][step] / 100.0 * ACCENT[step]
  if vel.positive?
    f0 = 40.0 * (2.0**(pattern[:pitch][step] / 100.0 * 3.0))
    dfam_hits << DfamHit.new(dfam_next, f0, vel, 0.0, 0.0, S::Ladder.new(rate: RATE), 0.35 + (0.3 * (step % 2)))
  end
b = dfam_step % 5
if pattern_b[:velocity][b].positive?
  fb = 40.0 * (2.0**(pattern_b[:pitch][b] / 100.0 * 3.0))
  dfam_hits << DfamHit.new(dfam_next + 0.004, fb, pattern_b[:velocity][b] / 100.0 * 0.55, 0.0, 0.0, S::Ladder.new(rate: RATE), b.even? ? 0.25 : 0.75)
end
# The kick on every beat: four steps of the sequencer.
kicks << dfam_next if (dfam_step % 4).zero?
dfam_step += 1
  if (dfam_step % 32).zero?
    k = dfam_rng.rand(8)
    pattern[:pitch][k] = (pattern[:pitch][k] + dfam_rng.rand(-18..18)).clamp(5, 95)
    pattern[:velocity][k] = dfam_rng.rand < 0.15 ? 0 : (pattern[:velocity][k] + dfam_rng.rand(-20..20)).clamp(35, 100)
  end
  dfam_next += DFAM_STEP
end
kv = DFAM_KNOBS.transform_values { |k| k.step(n.to_f / RATE, tb) }
if tb > next_gesture
  name = DFAM_KNOBS.keys.sample(random: knob_rng)
  target = knob_rng.rand < 0.5 ? knob_rng.rand(0.0..0.15) : knob_rng.rand(0.85..1.0)
  DFAM_KNOBS[name].lean(target, BAR * knob_rng.rand(0.5..1.5), tb)
  LOG.puts "  dfam: #{name} -> #{target > 0.5 ? "up" : "down"}"
  next_gesture = tb + knob_rng.rand(6.0..16.0)
end
vcf = kv[:vcf_decay]
vca = kv[:vca_decay]
cut_top = kv[:cutoff]
dfam_hits.each do |h|
  pitch_env = cut = amp = 0.0
  j = 0
  while j < n
    tt = tb + (j.to_f / RATE) - h.start
    if tt >= 0
      if (j & 15).zero?
        pitch_env = 1.0 + (kv[:pitch_amount] * Math.exp(-tt / kv[:pitch_decay]))
        cut = 120.0 + (cut_top * Math.exp(-tt / vcf))
        amp = h.vel * Math.exp(-tt / vca) * DFAM_LEVEL
      end
      h.ph1 = (h.ph1 + (h.f0 * pitch_env / RATE)) % 1.0
      tri = S.wave(:triangle, h.ph1)
      h.ph2 = (h.ph2 + (h.f0 * 1.5 * pitch_env * (1.0 + (kv[:fm] * tri)) / RATE)) % 1.0
      sq = h.ph2 < 0.5 ? 1.0 : -1.0
      mix = (0.55 * tri) + (0.3 * sq) + (kv[:noise] * (rand * 2.0 - 1.0))
      out = h.ladder.process(mix, cut, kv[:resonance]) * amp
      left[j] += out * h.pan
      right[j] += out * (1.0 - h.pan)
    end
    j += 1
  end
end
dfam_hits.reject! { |h| tb - h.start > vca * 8 }
j = 0
while j < n
  now = tb + (j.to_f / RATE)
  bus = 0.0
  kicks.each do |t|
    tk = now - t
    next if tk.negative? || tk > 0.5

    phase = (50.0 * tk) + (170.0 * 0.012 * (1.0 - Math.exp(-tk / 0.012))) + (30.0 * 0.08 * (1.0 - Math.exp(-tk / 0.08)))
    bus += Math.sin(2 * Math::PI * phase) * Math.exp(-tk / 0.34)
    if tk < 0.003
      click_lp += 0.35 * ((rand * 2.0 - 1.0) - click_lp)
      bus += (click_lp * 1.2) + (tk < 0.0008 ? 0.6 : 0.0)
    end
  end
  k = Math.tanh(bus * 1.8) * KICK_LEVEL
  left[j] += k
  right[j] += k
  j += 1
end
kicks.reject! { |t| tb - t > 0.5 }
pcm = Array.new(n * 4)
n.times do |i|
  pcm[i * 4] = (Math.tanh(left[i] * 1.4) * 26_000).round
  pcm[(i * 4) + 1] = (Math.tanh(right[i] * 1.4) * 26_000).round
  pcm[(i * 4) + 2] = (Math.tanh(arp_l[i] * 1.4) * 26_000).round
  pcm[(i * 4) + 3] = (Math.tanh(arp_r[i] * 1.4) * 26_000).round
end
sox.write(pcm.pack("s<*"))
  frame += n
end
sox.close
