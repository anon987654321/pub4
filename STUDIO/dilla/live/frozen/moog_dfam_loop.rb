# Live: a progression through dilla's own oscillators and Moog ladder, a
# different moog patch every two chords, cutoff and resonance swept slowly while
# it plays. Streams raw PCM to sox, so nothing is written to disk.
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
PADS = %i[warm_pad poly_strings prophet_five juno_pad]
BAR = 4.4
LOOPS = (ARGV[0] || 2).to_i

Voice = Struct.new(:hz, :spec, :start, :held, :gain, :phases, :ladder, :bass)

def voice(midi, spec, start, held, gain, bass: false)
  rng = Random.new(midi * 7 + (start * 10).to_i)
  Voice.new(hz(midi) * 2.0**(rng.rand(-0.7..0.7) / 1200.0), spec, start, held, gain,
            spec[:waves].map { rng.rand }, S::Ladder.new(rate: RATE), bass)
end

voices = []
t0 = 0.0
LOOPS.times do |loop_i|
  CHORDS.each_with_index do |(bass, tones), i|
    pad = P.fetch(PADS[((loop_i * CHORDS.size) + i) / 2 % PADS.size])
    tones.each { |m| voices << voice(m, pad, t0, BAR - 0.1, 0.22) }
    # Moog bass: the chord root twice a bar, the second a little late.
    voices << voice(bass, P[:moog_bass], t0, 1.6, 0.55, bass: true)
    voices << voice(bass, P[:moog_bass], t0 + 2.35, 1.2, 0.45, bass: true)
    t0 += BAR
  end
end
total = t0 + 2.5

# The knobs: cutoff breathes over 23 s, resonance over 31 s, out of phase.
def cutoff_knob(t) = 0.55 + 0.45 * Math.sin(2 * Math::PI * t / 23.0)
def res_knob(t) = 0.5 + 0.5 * Math.sin(2 * Math::PI * t / 31.0 + 1.3)

# The DFAM, as the Moog is built: an 8-step sequencer, each step its own pitch
# and velocity, running in sixteenths; VCO 1 a triangle frequency-modulating
# VCO 2, a square; both with a pitch envelope that falls; noise mixed in; all
# of it through a ladder low-pass with its own decay, then the VCA's decay.
# The pattern starts from dilla's DfamEngine and one step mutates every two
# bars; decay and cutoff drift slowly, like the pads' knobs.
DFAM_STEP = BAR / 16
DFAM_LEVEL = 0.34
pattern = { pitch: [50, 30, 60, 20, 55, 35, 65, 25], velocity: [80, 60, 90, 50, 85, 65, 95, 55] }
dfam_rng = Random.new
dfam_hits = []
dfam_next = 0.0
dfam_step = 0
DfamHit = Struct.new(:start, :f0, :vel, :ph1, :ph2, :ladder, :pan)
def vcf_decay_knob(t) = 0.05 + 0.1 * (0.5 + 0.5 * Math.sin(2 * Math::PI * t / 37.0))
def vca_decay_knob(t) = 0.09 + 0.12 * (0.5 + 0.5 * Math.sin(2 * Math::PI * t / 29.0 + 0.7))
def dfam_cut_knob(t) = 900.0 + 2600.0 * (0.5 + 0.5 * Math.sin(2 * Math::PI * t / 43.0 + 2.1))

$stderr.puts "live: #{CHORDS.size * LOOPS} chords, #{PADS.join(" -> ")} over moog_bass, #{total.round}s"
sox = IO.popen(%W[sox -q -t raw -r #{RATE} -e signed -b 16 -c 2 - -d], "wb")
frame = 0
frames = (total * RATE).to_i
two_pi = 2 * Math::PI
while frame < frames
  n = [BLOCK, frames - frame].min
  left = Array.new(n, 0.0)
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
    base_cut = spec[:cutoff] * (v.bass ? 0.7 + ck * 0.8 : 0.35 + ck * 1.6)
    res = v.bass ? spec[:resonance] : [spec[:resonance] + rk * 0.45, 0.85].min
    j = 0
    while j < n
      t = tb + (j.to_f / RATE) - v.start
      if t >= 0
        raw = 0.0
        spec[:waves].each_with_index do |shape, k|
          v.phases[k] = (v.phases[k] + (freqs[k] / RATE)) % 1.0
          raw += S.wave(shape, v.phases[k]) * level
        end
        cut = base_cut + (spec[:env_amount] * spec[:filter_env].at(t, v.held))
        out = v.ladder.process(raw * spec[:drive], cut.clamp(30.0, 12_000.0), res) * spec[:amp].at(t, v.held) * v.gain
        left[j] += out * 0.52
        right[j] += out * 0.48
      end
      j += 1
    end
  end
voices.reject! { |v| tb > v.start + v.held + v.spec[:amp].release }

# Sequence the DFAM a block ahead.
while dfam_next < tb + (n.to_f / RATE)
  step = dfam_step % 8
  vel = pattern[:velocity][step] / 100.0
  if vel.positive?
    f0 = 40.0 * (2.0**(pattern[:pitch][step] / 100.0 * 3.0))
    dfam_hits << DfamHit.new(dfam_next, f0, vel, 0.0, 0.0, S::Ladder.new(rate: RATE), 0.35 + (0.3 * (step % 2)))
  end
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
  sox.write(left.zip(right).flatten.map { |s| (Math.tanh(s * 1.4) * 26_000).round }.pack("s<*"))
  frame += n
end
sox.close
