# -------------------------------------------------------------- tape echo
# A space echo: three playback heads read one loop at 1x, 2x and 3x the base delay. The
# heads in use are summed, darkened by a lowpass and a mild saturation, and fed back, so each
# repeat is quieter and duller than the last. No modulation: the tape runs true.
module Echo
  MAX_INTENSITY = 0.9 # feedback never reaches one, so the loop cannot run away

  def self.process(buf, delay:, heads: [1, 2], intensity: 0.5, volume: 0.45, lowpass: 3200, saturation: 0.35, reverb: 0.0, tail: 4.0, resets: [])
    intensity = intensity.to_f.clamp(0.0, MAX_INTENSITY)
    d = [(delay * SAMPLE_RATE).round, 1].max
    ring = Array.new((heads.max * d) + 1, 0.0)
    tail = (tail * SAMPLE_RATE).to_i # the repeats ring on after the last note and die away of themselves
    cutoff = lowpass ? 1.0 / ((2 * Math::PI * lowpass * (1.0 / SAMPLE_RATE)) + 1.0) : 0.0
    drive = 1.0 + (2.0 * saturation)
    share = 1.0 / heads.size
    y = 0.0
    wet = Array.new(buf.size + tail, 0.0)
    cuts = resets.to_h { |at| [at, true] }
    wet.each_index do |n|
      if cuts[n] # a chord changes: what the heads still hold belongs to the old chord and goes quiet
        ring.fill(0.0)
        y = 0.0
      end
      taps = 0.0
      heads.each { |h| taps += ring[(n - (h * d)) % ring.size] }
      y += (1.0 - cutoff) * ((Math.tanh(taps * share * drive) / drive) - y)
      wet[n] = y
      ring[n % ring.size] = (n < buf.size ? buf[n] : 0.0) + (intensity * y)
    end
    wet = FX.reverb(wet, reverb) if reverb.to_f.positive?
    Array.new(wet.size) { |n| (n < buf.size ? buf[n] : 0.0) + (volume * wet[n]) }
  end
end

