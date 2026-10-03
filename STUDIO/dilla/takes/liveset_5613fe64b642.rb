# MASTER's main sound, improvising live and endless: soul-jazz harmony chosen
# chord by chord, each voiced nearest the last, the key moving on its own.
# The chords play only Moog presets on dilla's ladder, morphing over four
# chords, whole and uncut; the turntablist's crossfader waits behind
# CUTS_ON. A hand still works the record now and then: a tape stop, a
# spinback at the end of some phrases, a dub delay throw. Over it, quiet dry
# Rhodes arpeggios; under it the rolling Moog bass, an industrial grid at
# 128 BPM and the DFAM, always changing. Kicks sit off: KICKS_ON.
$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
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
# The Rhodes leads: dilla's two electric pianos, and each a shade brighter
# and darker.
RHODES_LEADS = {
  rhodes_tine: P[:rhodes_tine], e_piano: P[:e_piano],
  rhodes_bright: P[:rhodes_tine].merge(cutoff: P[:rhodes_tine][:cutoff] * 1.6),
  e_piano_dark: P[:e_piano].merge(cutoff: P[:e_piano][:cutoff] * 0.65),
}.freeze
P.merge!(RHODES_LEADS)
# Moog chord presets, on dilla's ladder: the chords play only these, the
# patch morphing from one to the next without a seam -- cutoff, resonance,
# envelope depth, drive and detune all glide; the waves change at halfway.
MOOG_ENV = { amp: P[:warm_pad][:amp], filter_env: P[:warm_pad][:filter_env] }.freeze
MOOG_CHORDS = {
  minimoog_pad: { waves: %i[saw square triangle], detune: [0.0, -6.0, 7.0], octaves: [0, 0, -1], cutoff: 620.0, env_amount: 1400.0, resonance: 0.42, drive: 1.1 },
  memorymoog_brass: { waves: %i[saw saw saw], detune: [-9.0, 0.0, 9.0], octaves: [0, 0, 0], cutoff: 760.0, env_amount: 1900.0, resonance: 0.3, drive: 1.2 },
  polymoog_vox: { waves: %i[square square saw], detune: [-4.0, 5.0, 0.0], octaves: [0, 1, 0], cutoff: 900.0, env_amount: 700.0, resonance: 0.24, drive: 0.95 },
  moog_one_strings: { waves: %i[saw saw saw], detune: [-14.0, 0.0, 13.0], octaves: [0, 0, 1], cutoff: 1150.0, env_amount: 800.0, resonance: 0.2, drive: 0.9 },
  sub37_warm: { waves: %i[saw square saw], detune: [0.0, 4.0, -5.0], octaves: [0, -1, 0], cutoff: 480.0, env_amount: 1600.0, resonance: 0.55, drive: 1.3 },
}.transform_values { |p| p.merge(MOOG_ENV) }.freeze
# Four chords to travel from one preset to the next, in a fresh order each lap.
MORPH_CHORDS = 4
def moog_morph(order, chord_i)
  pos = chord_i.to_f / MORPH_CHORDS
  a = MOOG_CHORDS.fetch(order[pos.floor % order.size])
  b = MOOG_CHORDS.fetch(order[(pos.floor + 1) % order.size])
  x = pos - pos.floor
  lerp = ->(k) { a[k] + ((b[k] - a[k]) * x) }
  (x < 0.5 ? a : b).merge(cutoff: lerp.(:cutoff), env_amount: lerp.(:env_amount), resonance: lerp.(:resonance),
                           drive: lerp.(:drive), detune: a[:detune].each_index.map { |i| a[:detune][i] + ((b[:detune][i] - a[:detune][i]) * x) })
end
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
# Industrial techno, ten below the 128 BPM it started at (Attack Magazine:
# 126-130), at the operator's word. BAR is two bars, eight beats.
BPM = 118
BAR = 8 * 60.0 / BPM
CHORD_LEN = BAR
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
moog_order = nil
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
DFAM_STEP = BAR / 32 # sixteenths
DFAM_LEVEL = 0.16
pattern = { pitch: [50, 30, 60, 20, 55, 35, 65, 25], velocity: [80, 60, 90, 50, 85, 65, 95, 55] }
dfam_rng = Random.new
dfam_hits = []
dfam_next = 0.0
dfam_step = 0
pattern_b = { pitch: [78, 64, 88, 70, 92], velocity: [55, 0, 70, 45, 60] }
# Accents on the eight-step page: the downbeat and the and-of-two lean in.
DFAM_SCENES = %i[euclid ratchet broken tribal].freeze
# Each groove brings its own kick, as [cycle length, steps that hit].
SCENE_KICKS = { euclid: [16, [0, 6, 10]], ratchet: [12, [0, 7]], broken: [16, [0, 3, 10, 11]], tribal: [12, [0, 5, 8]] }.freeze
dfam_scene = nil
next_scene_at = 0.0
grid_next = 0.0
grid_step = 0
DFAM_RATES = { 1.0 => "16ths", (2.0 / 3) => "triplets", 0.5 => "32nds", 1.5 => "dotted 16ths", 2.0 => "8ths" }.freeze
# A Euclidean rhythm: k hits spread as evenly as n steps allow.
def euclid(k, n) = (@euclid ||= {})[[k, n]] ||= Array.new(n) { |i| ((i * k) % n) < k }
# And its own lead rhythm, on sixteen steps.
SCENE_LEAD = { euclid: euclid(5, 16), ratchet: euclid(6, 16), broken: Array.new(16) { |i| [0, 3, 6, 10, 12].include?(i) }, tribal: euclid(7, 16) }.freeze
# A new groove, never the kind just played: its kind, its rate, and for a
# generated one a Euclidean pattern of 2 to n-1 hits over 5 to 16 steps.
new_scene = lambda do |last|
  kind = (DFAM_SCENES + %i[generated generated]).reject { |k| k == last && k != :generated }.sample(random: dfam_rng)
  rate, rate_name = DFAM_RATES.to_a.sample(random: dfam_rng)
  steps = dfam_rng.rand(5..16)
  hits = dfam_rng.rand(2..(steps - 1))
  label = kind == :generated ? "E(#{hits},#{steps}) in #{rate_name}" : "#{kind} in #{rate_name}"
  { kind:, rate:, label:, hits: euclid(hits, steps).rotate(dfam_rng.rand(steps)),
    pitches: Array.new(dfam_rng.rand(3..8)) { dfam_rng.rand(5..45) } }
end
ACCENT = [1.35, 0.8, 1.0, 0.85, 1.25, 0.8, 1.1, 0.9].freeze
KICK_LEVEL = 0.06
# Off at the operator's word, and with them the rumble and the pump.
KICKS_ON = false
# The crossfader is off at the operator's word: the chords play whole on
# deck A, the morphing preset, and deck B is not voiced. true brings the
# turntablist's cuts back.
CUTS_ON = false
# The lead plays over every chord, at the operator's word.
LEAD_ALWAYS = true
# Muted at the operator's word; true brings the leads back.
LEADS_ON = true
kicks = []
click_lp = 0.0
# Turntablism on the pads: a scratch DJ's sharp-curve crossfader, two decks
# (the two Moog layers) cut hard on the thirty-second grid. Each pattern is
# 32 steps, one bar: A is deck A open, B deck B, - the fader closed. The
# fader moves in half a millisecond, so every cut is a cut, not a blend.
CUTS = {
  transformer: "A-A-A-A-A-A-A-A-A-A-A-A-A-A-A-A-",
  slow_transformer: "AA--AA--AA--AA--BB--BB--BB--BB--",
  crab: "A-A-A-A-AAAAAAAAB-B-B-B-BBBBBBBB",
  chirp: "AAA-----AAA-----BBB-----BBB-----",
  orbit: "A--AA--AA--AA--AB--BB--BB--BB--B",
  flare: "AAAA-AAA-AAAAAAAAAAA-AAA-AAAAAAA",
  ab_chop: "AAAABBBBAAAABBBB--AABB--AABBAB--",
  tear: "AAAAAAAA--------A-A-AAAA--------",
}.freeze
cut_name = :transformer
cut_bar = -1
gain_a = 1.0
gain_b = 0.0
# The record under the crossfader: the cut pads write into three seconds of
# buffer and are read back at a delay d that is zero in plain play, so the
# deck adds no latency. A hand on the record moves d: the read speed is
# 1 - d', so a growing d drops the pitch and a shrinking one raises it.
#   baby      d rises and falls over a sixteenth: the push and pull.
#   tape_stop the speed falls from 1 to 0 over a beat, the level with it.
#   spinback  the record thrown backwards at three times speed, fading.
DECK_LEN = RATE * 3
deck_l = Array.new(DECK_LEN, 0.0)
deck_r = Array.new(DECK_LEN, 0.0)
deck_w = 0
deck_fx = nil # [kind, start]
last_s32 = -1
last_deck = "-"
# The dub throw: a send, open for the bar's last eighth when it fires, into
# a dotted-eighth echo that darkens and thins as it repeats.
DUB_LEN = RATE
DUB_DELAY = (3 * DFAM_STEP * RATE).round
dub_l = Array.new(DUB_LEN, 0.0)
dub_r = Array.new(DUB_LEN, 0.0)
dub_w = 0
dub_lp_l = dub_lp_r = dub_hp_l = dub_hp_r = 0.0
dub_send = 0.0
dub_throw = false
DUB_LP = 1.0 - Math.exp(-2 * Math::PI * 1800.0 / RATE)
DUB_HP = 1.0 - Math.exp(-2 * Math::PI * 220.0 / RATE)
CUT_GLIDE = 1.0 - Math.exp(-1.0 / (0.005 * RATE))
# The Crystallizer, after Soundtoys: reversed grains of the lead, pitched up
# an octave or a fifth, a quarter second late, fed back into themselves.
# Two readers half a grain apart, Hann-windowed, crossfade into a shimmer.
CRYS_LEN = RATE * 2
CRYS_GRAIN = (RATE * 0.16).round
CRYS_DELAY = (RATE * 0.25).round
CRYS_FEEDBACK = 0.45
CRYS_MIX = 0.5
crys_l = Array.new(CRYS_LEN, 0.0)
crys_r = Array.new(CRYS_LEN, 0.0)
crys_w = 0
crys_p = 0
crys_pitch = 2.0
crys_out_l = crys_out_r = 0.0
hats = []
claps = []
# The 909's hat: six detuned square waves, high-passed, then crushed to 12
# bits the way an SP-1200 resample crunches it.
HAT_HZ = [205.3, 304.4, 369.6, 522.7, 540.0, 800.0].freeze
HAT_LEVEL = 0.011
# Rendered once: the squares, noise under them for grit, and the decay.
hat_table = lambda do |len, decay|
  Array.new((len * RATE).to_i) do |i|
    th = i.to_f / RATE
    sq = HAT_HZ.sum { |f| ((th * f * 7.0) % 1.0) < 0.5 ? 1.0 : -1.0 }
    (sq + (((rand * 2.0) - 1.0) * 3.0)) * Math.exp(-th / decay)
  end.freeze
end
HAT_OPEN = hat_table.(0.3, 0.07)
HAT_CLOSED = hat_table.(0.06, 0.015)
# The shaker: noise alone, short, high-passed with the hats.
SHAKER = Array.new((0.08 * RATE).to_i) { |i| ((rand * 2.0) - 1.0) * 2.0 * Math.exp(-i.to_f / RATE / 0.025) }.freeze
CLAP_LEVEL = 0.08
hat_lp = clap_lp = clap_hp = 0.0
# The rumble: the kick sent into a dark reverb (three combs), distorted,
# low-passed to 150 Hz, mono, and ducked by the kick itself.
RUMBLE_LEVEL = 0.05
COMBS = [1123, 1409, 1693].map { |len| Array.new(len, 0.0) }
comb_i = [0, 0, 0]
rum_lp1 = rum_lp2 = 0.0
RUM_A = 1.0 - Math.exp(-2 * Math::PI * 150.0 / RATE)
HAT_A = 1.0 - Math.exp(-2 * Math::PI * 7000.0 / RATE)
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
ARP_FX = "anull"
# Extreme analog tape on the master channel, the whole sum: the head bump near
# 60 Hz, the drive into tanh that tape saturation is (undone after, so it
# colours rather than raises), the capstan's wow and flutter worn deep, the top
# the tape cannot hold, and its hiss.
def tape(drive:, wow:, flutter:, top:, hiss:)
  "equalizer=f=60:t=q:w=1.1:g=4.5,volume=#{drive},asoftclip=type=tanh,volume=#{(1.0 / drive).round(3)}," \
    "vibrato=f=0.42:d=#{wow},vibrato=f=6.8:d=#{flutter},lowpass=f=#{top},highpass=f=28," \
    "aeval=exprs=val(0)+#{hiss}*(2*random(0)-1)|val(1)+#{hiss}*(2*random(1)-1):c=same"
end
TAPE = tape(drive: 3.2, wow: 0.22, flutter: 0.07, top: 9_500, hiss: 0.004)
# Arps on the arps, at the operator's word: the lead is split three ways. One
# stays dry; one goes up a fifth and comes back an eighth late, the other up
# an octave a dotted eighth late, so the echoes arpeggiate over the arpeggio.
# Each pitched copy feeds back through its own echo the way a crystallizer
# does, and the sum is sharpened with ffmpeg's crystalizer. The pitch shift is
# asetrate then atempo, a resample and a time-stretch, which grains the copies.
def pitched(ratio, delay_ms, echo_ms, decay)
  "asetrate=#{(RATE * ratio).round},aresample=#{RATE},atempo=#{(1.0 / ratio).round(4)}," \
    "adelay=#{delay_ms}|#{delay_ms},aecho=0.8:0.7:#{echo_ms}:#{decay}"
end
EIGHTH = (BAR / 16 * 1000).round
ARPS_ON_ARPS = "asplit=3[ad][ax][ay];[ax]#{pitched(1.5, EIGHTH, EIGHTH * 2, 0.45)}[af];" \
               "[ay]#{pitched(2.0, (EIGHTH * 1.5).round, EIGHTH * 3, 0.4)},highpass=f=900[ao];" \
               "[ad][af][ao]amix=inputs=3:weights=1 0.5 0.35:normalize=0,crystalizer=i=1.5"
# The leads sit lower in the sum, at the operator's word: 0.9 against the
# main's 1 where they were 1.5.
GRAPH = "[0:a]pan=stereo|c0=c0|c1=c1,#{MASTER}[m];[0:a]pan=stereo|c0=c2|c1=c3,#{ARPS_ON_ARPS}[a];[m][a]amix=inputs=2:weights=1 0.9:normalize=0,#{TAPE},alimiter=limit=0.96"
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
    moog_order = MOOG_CHORDS.keys.shuffle(random: rng) if (chord_i % (MORPH_CHORDS * MOOG_CHORDS.size)).zero?
    pad = moog_morph(moog_order, chord_i)
    pad_name = "#{moog_order[(chord_i / MORPH_CHORDS) % moog_order.size]} -> #{moog_order[((chord_i / MORPH_CHORDS) + 1) % moog_order.size]} #{(chord_i % MORPH_CHORDS) * 100 / MORPH_CHORDS}%"
    bass_patch = P.fetch(BASSES[(chord_i / 4) % BASSES.size])
    voicing.each { |m| voices << voice(m, pad, next_chord, CHORD_LEN - 0.1, 0.3, bass: :pad) }
    # The second layer, crossfaded against the first on a rhythm: the preset
    # two stops further round the Moog wheel, so the two never sound alike.
    pad_b = MOOG_CHORDS.fetch(moog_order[((chord_i / MORPH_CHORDS) + 2) % moog_order.size])
    voicing.each { |m| voices << voice(m, pad_b, next_chord, CHORD_LEN - 0.1, 0.3, bass: :pad_b) } if CUTS_ON
    # The rolling bass: the root on the three sixteenths after every kick,
    # short and even, the octave up on the last of each beat now and then.
    (CHORD_LEN / (BAR / 8)).round.times do |beat|
      [1, 2, 3].each do |sixteenth|
        up = sixteenth == 3 && rng.rand < 0.25 ? 12 : 0
        voices << voice(bass + up, bass_patch, next_chord + (beat * BAR / 8) + (sixteenth * DFAM_STEP), DFAM_STEP * 0.6, 0.4, bass: true)
      end
    end
    LOG.puts "#{Time.now.strftime("%H:%M:%S")} #{name} on #{pad_name}, bass #{BASSES[(chord_i / 4) % BASSES.size]}"
    if LEADS_ON && (LEAD_ALWAYS || rng.rand < 0.3)
      # The loved lead, dry: an arpeggio over the chord an octave up, its shape
      # drawn fresh, a new patch every four notes across every lead the synth has.
      arp_patches = RHODES_LEADS.keys.shuffle(random: rng)
      # An octave lower than before, and always climbing: the chord, then the
      # chord an octave up, arped upward.
      order = (voicing + voicing.map { |m| m + 12 }).sort
      step = BAR / 16
      16.times { |k| voices << voice(order[k % order.size], P.fetch(arp_patches[(k / 4) % arp_patches.size]), next_chord + (k * step), step * 0.7, 0.18, bass: :arp) }
      LOG.puts "  arp over it"
    end
    chord_i += 1
    next_chord += CHORD_LEN
  end
  n = BLOCK
  left = Array.new(n, 0.0)
  arp_l = Array.new(n, 0.0)
  arp_r = Array.new(n, 0.0)
  right = Array.new(n, 0.0)
  pad_l = Array.new(n, 0.0)
  padb_l = Array.new(n, 0.0)
  padb_r = Array.new(n, 0.0)
  pad_r = Array.new(n, 0.0)
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
    out_l, out_r = case v.bass
                   when :arp then [arp_l, arp_r]
                   when :pad then [pad_l, pad_r]
                   when :pad_b then [padb_l, padb_r]
                   else [left, right]
                   end
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

# Sequence the DFAM a block ahead, on its own clock. Every two to six bars
# a new groove is drawn: one of the four named ones or a fresh Euclidean
# pattern, at a rate of its own against the steady kick -- sixteenths,
# triplets, thirty-seconds, dotted sixteenths or eighths. While it plays,
# its pitches and its rotation keep mutating.
while dfam_next < tb + (n.to_f / RATE)
  if dfam_scene.nil? || dfam_next >= next_scene_at
    dfam_scene = new_scene.(dfam_scene && dfam_scene[:kind])
    next_scene_at = dfam_next + ((BAR / 2) * dfam_rng.rand(2..6))
    LOG.puts "  dfam groove -> #{dfam_scene[:label]}"
  end
  step_len = DFAM_STEP * dfam_scene[:rate]
  hz = ->(p) { 32.0 * (2.0**(p / 100.0 * 4.0)) }
  add = ->(at, p, vel, pan) { dfam_hits << DfamHit.new(at, hz.(p), vel, 0.0, 0.0, S::Ladder.new(rate: RATE), pan) }
  pitches = dfam_scene[:pitches]
  case dfam_scene[:kind]
  when :generated
    if dfam_scene[:hits][dfam_step % dfam_scene[:hits].size]
      add.(dfam_next, pitches[dfam_step % pitches.size], dfam_rng.rand < 0.25 ? 1.1 : dfam_rng.rand(0.5..0.85), dfam_rng.rand(0.25..0.75))
    end
  when :euclid
    add.(dfam_next, pitches[dfam_step % pitches.size], 1.0, 0.45) if euclid(5, 16)[dfam_step % 16]
  when :ratchet
    if (dfam_step % 6).zero? || dfam_rng.rand < 0.12
      reps = dfam_rng.rand(2..4)
      p0 = dfam_rng.rand(25..45)
      reps.times { |r| add.(dfam_next + (r * step_len / 2), p0 - (r * 12), 0.9 - (r * 0.15), 0.3 + (0.4 * (r % 2))) }
    end
  when :broken
    add.(dfam_next, pitches[6 - (dfam_step % 7)] || pitches.first, dfam_rng.rand(0.4..1.0), dfam_rng.rand(0.2..0.8)) if dfam_rng.rand < 0.6
  when :tribal
    t12 = dfam_step % 12
    add.(dfam_next, pitches[t12 % pitches.size], [0, 3, 6].include?(t12) ? 1.1 : 0.6, 0.35 + (0.3 * (t12 % 2))) if euclid(7, 12)[t12]
  end
  # The mutation: now and then a pitch redrawn, the pattern turned a step.
  pitches[dfam_rng.rand(pitches.size)] = dfam_rng.rand(5..45) if dfam_rng.rand < 0.07
  dfam_scene[:hits] = dfam_scene[:hits].rotate(1) if dfam_rng.rand < 0.03
  dfam_step += 1
  dfam_next += step_len
end
# The industrial grid, after Attack Magazine's dissection: the kick four
# on the floor, a closed hat on each offbeat, a shaker on every second
# offbeat, a noise snare on two and four. The DFAM is the syncopated low tom.
while grid_next < tb + (n.to_f / RATE)
  s16 = grid_step % 16
  kicks << grid_next if KICKS_ON && (s16 % 4).zero?
  hats << [grid_next, HAT_CLOSED, 0.9] if s16 % 4 == 2
  hats << [grid_next + 0.004, SHAKER, 0.6] if [6, 14].include?(s16)
  claps << grid_next if [4, 12].include?(s16)
  grid_step += 1
  grid_next += DFAM_STEP
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
  bar = (tb / (BAR / 2)).floor
if bar != cut_bar
  cut_bar = bar
cut_name = CUTS.keys.sample(random: rng)
bar_start = bar * (BAR / 2)
beat = 4 * DFAM_STEP
if (bar % 8) == 7 && rng.rand < 0.5
  deck_fx = [:spinback, bar_start + (3 * beat)]
  LOG.puts "  deck: spinback"
elsif rng.rand < 0.12
  deck_fx = [:tape_stop, bar_start + (3 * beat)]
  LOG.puts "  deck: tape stop"
end
dub_throw = rng.rand < 0.25
LOG.puts "  deck: dub throw" if dub_throw
  LOG.puts "  pads cut -> #{cut_name}"
end
cut = CUTS[cut_name]
j = 0
while j < n
  now = tb + (j.to_f / RATE)
  bus = 0.0
  duck = 0.0
  kicks.each do |t|
    tk = now - t
    next if tk.negative? || tk > 0.5

    d = Math.exp(-tk / 0.12)
    duck = d if d > duck
    phase = (50.0 * tk) + (170.0 * 0.012 * (1.0 - Math.exp(-tk / 0.012))) + (30.0 * 0.08 * (1.0 - Math.exp(-tk / 0.08)))
    bus += Math.sin(2 * Math::PI * phase) * Math.exp(-tk / 0.34)
    if tk < 0.003
      click_lp += 0.35 * ((rand * 2.0 - 1.0) - click_lp)
      bus += (click_lp * 1.2) + (tk < 0.0008 ? 0.6 : 0.0)
    end
  end
  # Driven into hard clipping and back: the distorted industrial kick.
  k = Math.tanh(Math.tanh(bus * 7.0) * 2.5)
  k = (k * 256).round / 256.0 * KICK_LEVEL # a bitcrusher for the crisp attack
  wet = 0.0
  c = 0
  while c < 3
    buf = COMBS[c]
    y = buf[comb_i[c]]
    buf[comb_i[c]] = k + (y * 0.8)
    comb_i[c] = (comb_i[c] + 1) % buf.size
    wet += y
    c += 1
  end
  rum_lp1 += RUM_A * (Math.tanh(wet * 12.0) - rum_lp1)
  rum_lp2 += RUM_A * (rum_lp1 - rum_lp2)
  rumble = rum_lp2 * RUMBLE_LEVEL * (1.0 - (0.9 * duck))
  metal = 0.0
  hats.each do |t, open, vel|
    idx = ((now - t) * RATE).to_i
    table = open
    metal += table[idx] * vel if idx >= 0 && idx < table.size
  end
  hat_lp += HAT_A * (metal - hat_lp)
  # Crushed to 12 bits and overdriven, the SP-1200 resample.
  hat = Math.tanh(((metal - hat_lp) * 32).round / 32.0 * 0.5) * 2.0 * HAT_LEVEL
  clap = 0.0
  claps.each do |t|
    tc = now - t
    next if tc.negative? || tc > 0.35

    burst = (1.0 - Math.exp(-tc / 0.004)) * Math.exp(-tc / 0.11)
    clap += ((rand * 2.0) - 1.0) * burst
  end
  clap_lp += 0.18 * (Math.tanh(clap * 2.5) - clap_lp)
  clap_hp += 0.05 * (clap_lp - clap_hp)
  drums = k + hat + ((clap_lp - clap_hp) * CLAP_LEVEL)
  # Parallel distortion on the drum bus: grit blended under the clean hits.
  drums += Math.tanh(drums * 12.0) * 0.025
  # The pads pump against the kick.
  pump = 1.0 - (0.25 * duck)
deck = CUTS_ON ? cut[(now / (DFAM_STEP / 2)).floor % 32] : "A"
gain_a += CUT_GLIDE * ((deck == "A" ? 1.0 : 0.0) - gain_a)
gain_b += CUT_GLIDE * ((deck == "B" ? 1.0 : 0.0) - gain_b)
pl = (pad_l[j] * gain_a) + (padb_l[j] * gain_b)
pr = (pad_r[j] * gain_a) + (padb_r[j] * gain_b)
# Baby scratches: a third of the cuts that open the fader get a hand on it.
s32 = (now / (DFAM_STEP / 2)).floor
if s32 != last_s32
  deck_fx = [:baby, now] if last_deck == "-" && deck != "-" && deck_fx.nil? && rng.rand < 0.12
  last_s32 = s32
  last_deck = deck
end
deck_l[deck_w] = pl
deck_r[deck_w] = pr
d = 0.0
deck_gain = 1.0
if deck_fx && now >= deck_fx[1]
  x = now - deck_fx[1]
  case deck_fx[0]
  when :baby
    len = DFAM_STEP
    if x < len
      d = 0.008 * (1.0 - Math.cos(2 * Math::PI * x / len)) / 2.0
    else
      deck_fx = nil
    end
  when :tape_stop
    len = 4 * DFAM_STEP
    if x < len
      d = x * x / (2.0 * len)
      deck_gain = 1.0 - (x / len)
    else
      deck_fx = nil
    end
  when :spinback
    if x < 0.5
      d = x < 0.1 ? 20.0 * x * x : 0.2 + (4.0 * (x - 0.1))
      deck_gain = 1.0 - (x / 0.5)
    else
      deck_fx = nil
    end
  end
end
if d.positive?
  pos = deck_w - (d * RATE)
  i0 = pos.floor
  frac = pos - i0
  a = i0 % DECK_LEN
  b = (i0 + 1) % DECK_LEN
  pl = ((deck_l[a] * (1.0 - frac)) + (deck_l[b] * frac)) * deck_gain
  pr = ((deck_r[a] * (1.0 - frac)) + (deck_r[b] * frac)) * deck_gain
elsif deck_gain < 1.0
  pl *= deck_gain
  pr *= deck_gain
end
deck_w = (deck_w + 1) % DECK_LEN
# The dub throw: the send opens for the bar's last eighth.
bar_pos = (now % (BAR / 2)) / (BAR / 2)
dub_send += 0.002 * ((dub_throw && bar_pos > 0.875 ? 1.0 : 0.0) - dub_send)
el = dub_l[(dub_w - DUB_DELAY) % DUB_LEN]
er = dub_r[(dub_w - DUB_DELAY) % DUB_LEN]
dub_lp_l += DUB_LP * (el - dub_lp_l)
dub_lp_r += DUB_LP * (er - dub_lp_r)
dub_hp_l += DUB_HP * (dub_lp_l - dub_hp_l)
dub_hp_r += DUB_HP * (dub_lp_r - dub_hp_r)
dub_l[dub_w] = (pl * dub_send) + ((dub_lp_r - dub_hp_r) * 0.6) # crossed: the echo walks
dub_r[dub_w] = (pr * dub_send) + ((dub_lp_l - dub_hp_l) * 0.6)
dub_w = (dub_w + 1) % DUB_LEN
pl += (dub_lp_l - dub_hp_l) * 0.7
pr += (dub_lp_r - dub_hp_r) * 0.7
left[j] += (pl * pump) + drums + rumble
right[j] += (pr * pump) + drums + rumble
# The Crystallizer on the lead.
cl = crys_out_l = 0.0
cr = crys_out_r = 0.0
2.times do |g|
  ph = (crys_p + (g * CRYS_GRAIN / 2)) % CRYS_GRAIN
  win = 0.5 - (0.5 * Math.cos(2 * Math::PI * ph / CRYS_GRAIN))
  at = (crys_w - CRYS_DELAY - ((CRYS_GRAIN - ph) * crys_pitch).to_i) % CRYS_LEN
  cl += crys_l[at] * win
  cr += crys_r[at] * win
end
crys_l[crys_w] = arp_l[j] + (cr * CRYS_FEEDBACK) # crossed, so the shimmer walks the field
crys_r[crys_w] = arp_r[j] + (cl * CRYS_FEEDBACK)
crys_w = (crys_w + 1) % CRYS_LEN
crys_p += 1
if crys_p >= CRYS_GRAIN * 24 # every few seconds, a fifth or an octave
  crys_p = 0
  crys_pitch = [2.0, 1.5, 2.0].sample(random: rng)
end
arp_l[j] += cl * CRYS_MIX
arp_r[j] += cr * CRYS_MIX
j += 1
end
kicks.reject! { |t| tb - t > 0.5 }
hats.reject! { |t, _, _| tb - t > 0.1 }
claps.reject! { |t| tb - t > 0.35 }
pcm = Array.new(n * 4)
n.times do |i|
  pcm[i * 4] = (Math.tanh(left[i]) * 29_000).round
  pcm[(i * 4) + 1] = (Math.tanh(right[i]) * 29_000).round
  pcm[(i * 4) + 2] = (Math.tanh(arp_l[i] * 1.4) * 26_000).round
  pcm[(i * 4) + 3] = (Math.tanh(arp_r[i] * 1.4) * 26_000).round
end
sox.write(pcm.pack("s<*"))
  frame += n
end
sox.close
