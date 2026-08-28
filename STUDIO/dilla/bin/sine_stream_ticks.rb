# The heartbeat, as a mechanism under load.
#
# It began as a sine so the pipeline could be heard to be alive. It is now the
# most-heard sound in the session and it is asked to be sharper: two pieces of
# wood under immense pressure, a chainsaw catching. That is a comb resonator
# ringing at a pitch it is being dragged through, ring modulated so the ring is
# metallic rather than tonal, wavefolded so the peaks turn back instead of
# rounding off, and hard clipped. Loud enough to cut, short enough not to tire.
src = File.read("/Users/mac/Music/dilla_sines/sine_stream.rb")
eval(src.split("cfg = dilla_resolve_config").first) # rubocop:disable Security/Eval
require "fileutils"

OUT = "/Users/mac/Music/dilla_sines/ticks"
FileUtils.mkdir_p(OUT)
Dir[File.join(OUT, "*.wav")].each { |f| FileUtils.rm_f(f) }

# Pitched high on purpose: the ear is most sensitive around 3-4 kHz, which is
# where a sound becomes piercing rather than merely loud.
FROM = [1180.0, 980.0, 1420.0, 1640.0, 860.0, 1320.0, 1780.0, 1050.0].freeze
TO = [340.0, 420.0, 260.0, 380.0, 300.0, 240.0, 410.0, 290.0].freeze
LEVEL = (ENV["TICK_LEVEL"] || "0.52").to_f

8.times do |i|
  secs = 0.30 + (i % 3) * 0.07
  n = (RATE * secs).to_i
  l = Array.new(n, 0.0)
  r = Array.new(n, 0.0)
  # A hard-edged source: FM with a high index and the carrier already square.
  fm_chord!(l, r, [FROM[i], FROM[i] * 1.497], FROM[i] / 2.0, secs, seed: i, gain: 0.8)
  # The drag. Sweeping the comb from high to low is the bite catching and
  # loading -- the pitch falls because the cut is meeting resistance.
  comb_resonator!(l, r, hz_from: FROM[i], hz_to: TO[i], feedback: 0.86, mix: 0.8)
  ring_mod!(l, r, hz: 137.0 + i * 31.0, drift_hz: 4.2, mix: 0.55)
  wave_fold!(l, r, amount: 2.8, mix: 0.75)
  # Clip, not saturate: rounding the peak is exactly the softness being asked
  # against here.
  n.times { |j| l[j] = l[j].clamp(-0.82, 0.82) * 1.22; r[j] = r[j].clamp(-0.82, 0.82) * 1.22 }
  # Presence lift where it hurts.
  k = 1.0 - Math.exp(-2 * Math::PI * 3200.0 / RATE)
  zl = 0.0
  zr = 0.0
  n.times do |j|
    zl += k * (l[j] - zl)
    zr += k * (r[j] - zr)
    l[j] += (l[j] - zl) * 0.9
    r[j] += (r[j] - zr) * 0.9
  end
  peak = (0...n).map { |j| [l[j].abs, r[j].abs].max }.max
  g = peak > 0.0001 ? LEVEL / peak : 0.0
  # Attack stays instant -- a fade-in is the opposite of pointy. Only the tail
  # is shaped, and only enough to stop it clicking off.
  tail = (RATE * 0.012).to_i
  n.times do |j|
    e = j > n - tail ? (n - j).to_f / tail : 1.0
    l[j] *= g * e
    r[j] *= g * e
  end
  write_wav(File.join(OUT, format("%02d.wav", i)), l, r)
end
puts "  wrote #{Dir[File.join(OUT, "*.wav")].size} chainsaw ticks at level #{LEVEL}"
