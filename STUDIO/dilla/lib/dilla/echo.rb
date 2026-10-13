# -------------------------------------------------------------- tape echo
# A space echo: three playback heads read one loop at 1x, 2x and 3x the base delay. The
# heads in use are summed, darkened by a lowpass and a mild saturation, and fed back, so each
# repeat is quieter and duller than the last. No modulation: the tape runs true.
module Echo
  MAX_INTENSITY = 0.9 # feedback never reaches one, so the loop cannot run away

  # `send`, when given, is a proc from a sample index to how much of the input reaches the tape
  # at that moment: the hand on the send knob, which a throw turns up for a bar.
  def self.process(buf, delay:, heads: [1, 2], intensity: 0.5, volume: 0.45, lowpass: 3200, saturation: 0.35, reverb: 0.0, tail: 4.0, resets: [], send: nil)
    line = Stream::EchoLine.new(delay:, heads:, intensity:, volume:, lowpass:, saturation:, resets:, send:)
    wet = line.wet(buf + Array.new((tail * SAMPLE_RATE).to_i, 0.0)) # the repeats ring on after the last note and die away of themselves
    wet = FX.reverb(wet, reverb) if reverb.to_f.positive?
    Array.new(wet.size) { |n| (n < buf.size ? buf[n] : 0.0) + (volume * wet[n]) }
  end
end
