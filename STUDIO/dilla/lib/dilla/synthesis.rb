# --------------------------------------------------------------- synthesis
module Synth
  def self.env(t, dur, attack: 0.01, release: 0.3)
    if t < attack
      t / attack
    elsif t > dur - release
      [(dur - t) / release, 0.0].max
    else
      1.0
    end
  end

  # A true single-frequency oscillator: no upper harmonics, detune, chorus or modulation.
  # Release begins after the gate, so short notes remain at full level until they end.
  def self.pure_note(freq, dur, amp: 0.2, release: 0.12, attack: 0.008)
    return [] unless freq.positive? && freq <= SAMPLE_RATE * NYQUIST_SHARE

    release = [release.to_f, 0.001].max
    n = ((dur + release) * SAMPLE_RATE).to_i
    phase = 0.0
    step = 2.0 * Math::PI * freq / SAMPLE_RATE
    Array.new(n) do |i|
      t = i.to_f / SAMPLE_RATE
      envelope =
        if t < attack
          t / attack
        elsif t < dur
          1.0
        else
          [1.0 - ((t - dur) / release), 0.0].max
        end
      sample = Math.sin(phase) * envelope * amp
      phase += step
      sample
    end
  end

  # One note = sum of four harmonics with optional per-note detune.
  def self.note(freq, dur, detune: 0.0, amp: 0.2, release: 0.3)
    n = (dur * SAMPLE_RATE).to_i
    out = Array.new(n, 0.0)
    partials = [[1.0, 1.0], [2.0, 0.35], [3.0, 0.15], [4.0, 0.08]]

    partials.each do |mult, pamp|
      f = freq * mult * (1.0 + detune)
      next if f > SAMPLE_RATE * NYQUIST_SHARE # a partial past the limit would fold back down: skip it
      phase = 0.0
      step = 2 * Math::PI * f / SAMPLE_RATE
      n.times do |i|
        t = i.to_f / SAMPLE_RATE
        out[i] += Math.sin(phase) * pamp * env(t, dur, release:)
        phase += step
      end
    end
    out.map { |s| s * amp }
  end

  # One chord = sum of its notes, each with alternating detune for warmth.
  def self.chord(freqs, dur, detune: 0.0, strum: 0.0)
    n = (dur * SAMPLE_RATE).to_i
    buf = Array.new(n, 0.0)
    freqs.each_with_index do |f, idx|
      d = detune * (idx.even? ? 1 : -1)
      note_buf = note(f, dur, detune: d, amp: 1.0 / freqs.size)
      late = (strum * idx * SAMPLE_RATE).to_i # each voice a little after the one below
      note_buf.each_with_index { |s, i| buf[i + late] += s if i + late < n }
    end
    buf
  end
end

