# Live: a progression through dilla's own oscillators and Moog ladder, a
# different moog patch every two chords, cutoff and resonance swept slowly while
# it plays. Streams raw PCM to sox, so nothing is written to disk.
$LOAD_PATH.unshift File.expand_path("~/Documents/GitHub/pub4/MASTER/tools/studio/dilla/lib")
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
  sox.write(left.zip(right).flatten.map { |s| (Math.tanh(s * 1.4) * 26_000).round }.pack("s<*"))
  frame += n
end
sox.close
