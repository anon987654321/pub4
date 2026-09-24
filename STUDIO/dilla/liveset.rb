# MASTER's main sound, improvising: the frozen default (default_sound.rb),
# with the chords chosen live instead of looped. It opens on the loved
# progression, then walks soul-jazz harmony, each chord voiced nearest the
# last, a new moog patch every two chords, the DFAM on top. Endless.
$LOAD_PATH.unshift File.expand_path("~/Documents/GitHub/pub4/STUDIO/dilla/lib")
require "sound"

RATE = 32_000
BLOCK = 1_024
S = AnalogSynth
P = S::PATCHES

def hz(midi) = 440.0 * (2.0**((midi - 69) / 12.0))

# Fm9, Bbm9, Eb13, Abmaj9, Dbmaj7#11, C7alt: soul-jazz, Dilla territory.
CHORDS = [
  [41, [56, 60, 63, 67]], [46, [56, 61, 65, 68]], [39, [55, 60, 61, 65]],
  [44, [55, 60, 63, 70]], [37, [60, 65, 67, 72]], [36, [58, 61, 64, 68]],
]
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
kicks = []
DfamHit = Struct.new(:start, :f0, :vel, :ph1, :ph2, :ladder, :pan)
def vcf_decay_knob(t) = 0.05 + 0.1 * (0.5 + 0.5 * Math.sin(2 * Math::PI * t / 37.0))
def vca_decay_knob(t) = 0.09 + 0.12 * (0.5 + 0.5 * Math.sin(2 * Math::PI * t / 29.0 + 0.7))
def dfam_cut_knob(t) = 900.0 + 2600.0 * (0.5 + 0.5 * Math.sin(2 * Math::PI * t / 43.0 + 2.1))

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
  vcs(depth: 0.3, smear: 2.8), "alimiter=limit=0.95"
].join(",")
def space_echo(head_ms, decays)
  taps = [1, 2, 3].map { |k| (head_ms * k).round }.join("|")
  "highpass=f=160,aecho=0.9:0.9:#{taps}:#{decays},lowpass=f=3200,chorus=0.9:0.9:25:0.35:0.6:1.8"
end
HEAD = BAR / 16 * 1000
ARP_FX = "anull"
GRAPH = "[0:a]pan=stereo|c0=c0|c1=c1,#{MASTER}[m];[0:a]pan=stereo|c0=c2|c1=c3,#{ARP_FX}[a];[m][a]amix=inputs=2:weights=1 1.5:normalize=0,alimiter=limit=0.96"
sox = IO.popen(["sh", "-c", "ffmpeg -loglevel error -f s16le -ar #{RATE} -ac 4 -i - -filter_complex '#{GRAPH}' -f s16le -ar #{RATE} -ac 2 - | sox -q -t raw -r #{RATE} -e signed -b 16 -c 2 - -d"], "wb")
frame = 0
frames = Float::INFINITY
two_pi = 2 * Math::PI
while frame < frames
  # The next chord, chosen a second before it sounds.
  while next_chord < (frame.to_f / RATE) + 1.0
    if chord_i < CHORDS.size
      bass, tones = CHORDS[chord_i]
      voicing = tones
      name = "loved #{chord_i + 1}"
    else
      degree, quality = state
      voicing = voice_lead(QUALITIES[quality].map { |iv| (key + degree + iv) % 12 }, voicing)
      bass = 36 + ((key + degree) % 12)
      bass += 12 if bass < 36
      name = "#{NAMES[(key + degree) % 12]}#{quality}"
      state = MOVES.fetch(state).sample(random: rng)
      if (chord_i % 24).zero? && state.first.zero?
        key = (key + [5, 3, 8, 10].sample(random: rng)) % 12
        state = [0, %i[m9 m11].sample(random: rng)]
      end
    end
    pad = P.fetch(PADS[chord_i % PADS.size])
    bass_patch = P.fetch(BASSES[(chord_i / 4) % BASSES.size])
    voicing.each { |m| voices << voice(m, pad, next_chord, BAR - 0.1, 0.22) }
    # Moog bass: the chord root twice a bar, the second a little late.
    voices << voice(bass, bass_patch, next_chord, 1.6, 0.55, bass: true)
    voices << voice(bass, bass_patch, next_chord + (BAR * 0.534), 1.2, 0.45, bass: true)
    LOG.puts "#{Time.now.strftime("%H:%M:%S")} #{name} on #{PADS[chord_i % PADS.size]}, bass #{BASSES[(chord_i / 4) % BASSES.size]}"
    if rng.rand < 0.3
      # A new patch every four notes, across every lead the synth has.
      arp_patches = %i[glass_bell e_piano poly_lead vapor_lead soft_reed ringtone_lead acid rhodes_tine].shuffle(random: rng)
      notes = voicing.map { |m| m + 12 }
      order = [notes, notes.reverse, notes + notes.reverse[1..-2], notes.shuffle(random: rng)].sample(random: rng)
      step = BAR / 16
      16.times { |k| voices << voice(order[k % order.size], P.fetch(arp_patches[(k / 4) % arp_patches.size]), next_chord + (k * step), step * 0.7, 0.45, bass: :arp) }
      LOG.puts "  arp over it"
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
          cut = (base_cut + (spec[:env_amount] * spec[:filter_env].at(t, v.held))).clamp(30.0, 12_000.0)
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
vcf = vcf_decay_knob(tb)
vca = vca_decay_knob(tb)
cut_top = dfam_cut_knob(tb)
dfam_hits.each do |h|
  j = 0
  while j < n
    tt = tb + (j.to_f / RATE) - h.start
    if tt >= 0
      pitch_env = 1.0 + (2.2 * Math.exp(-tt / 0.045))
      h.ph1 = (h.ph1 + (h.f0 * pitch_env / RATE)) % 1.0
      tri = S.wave(:triangle, h.ph1)
      h.ph2 = (h.ph2 + (h.f0 * 1.5 * pitch_env * (1.0 + (0.45 * tri)) / RATE)) % 1.0
      sq = h.ph2 < 0.5 ? 1.0 : -1.0
      mix = (0.55 * tri) + (0.3 * sq) + (0.18 * (rand * 2.0 - 1.0))
      cut = 120.0 + (cut_top * Math.exp(-tt / vcf))
      out = h.ladder.process(mix, cut, 0.55) * h.vel * Math.exp(-tt / vca) * DFAM_LEVEL
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

    bus += Math.sin(2 * Math::PI * ((45.0 * tk) + (105.0 * 0.035 * (1.0 - Math.exp(-tk / 0.035))))) * Math.exp(-tk / 0.32)
    bus += (tk < 0.005 ? (1.0 - (tk / 0.005)) * 0.5 : 0.0)
  end
  k = Math.tanh(bus * 2.8) * KICK_LEVEL
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
