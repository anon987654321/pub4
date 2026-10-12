#!/usr/bin/env ruby
# frozen_string_literal: true

# dilla.rb -- chord progressions, a little late, with drums that sit a little off the grid.
#
# Usage:
#   ruby dilla.rb --list
#   ruby dilla.rb --progression 3 --out out/three.wav
#   ruby dilla.rb --progression 3 --drums offbeat_inversion --profile early_snare_late_hats --out out/full.wav
#   ruby dilla.rb --random --midi out/random.mid --out out/random.wav
#   ruby dilla.rb --quick
#
# Everything it chooses from is in dilla.json (same directory): progressions as arrays of
# chord names, groove profiles, drum patterns. Voicings are worked out from the chord names.
# Writes 16-bit mono 44.1 kHz WAV, and with --midi a Standard MIDI File. Standard library only.

require 'json'
require 'optparse'
require 'fileutils'
require 'zlib'
require 'shellwords'

SAMPLE_RATE = 44_100
MAX_OFFSET = 0.035 # seconds: no role is ever moved further than this from its place
NYQUIST_SHARE = 0.45 # a partial above this share of the sample rate is skipped, never folded back
MAX_DETUNE = 0.0035
AUDIBLE_TOP_HZ = 14_000.0 # --transpose-wrap folds a note down by octaves until it is under this

# ---------------------------------------------------------------- WAV writer
module WAV
  def self.write(path, samples)
    data = samples.map { |s| (s * 32767).round.clamp(-32_768, 32_767) }.pack('s<*')

    header  = +"RIFF"
    header << [36 + data.bytesize].pack('V')
    header << "WAVE"
    header << "fmt "
    header << [16].pack('V')
    header << [1].pack('v')                    # PCM
    header << [1].pack('v')                    # mono
    header << [SAMPLE_RATE].pack('V')
    header << [SAMPLE_RATE * 2].pack('V')      # byte rate
    header << [2].pack('v')                    # block align
    header << [16].pack('v')                   # bits per sample
    header << "data"
    header << [data.bytesize].pack('V')

    File.binwrite(path, header + data)
  end
end

# ------------------------------------------------------------------- chords
# A chord name becomes notes here and nowhere else: the root or slash bass in the low octave,
# then the upper structure. Each upper note starts as near as it can be to the last chord, and
# a search over octave shifts then picks the voicing that moves least, keeps the top line
# smooth and leaves no neighbours closer than a whole tone. No chord tone is ever dropped
# for spacing; only the fifth, then the root when the bass plays it, give way to the voice cap.
module Chords
  NOTE_PC = { 'C' => 0, 'D' => 2, 'E' => 4, 'F' => 5, 'G' => 7, 'A' => 9, 'B' => 11 }.freeze
  ACCIDENTAL = { 'b' => -1, '#' => 1, '' => 0 }.freeze

  # "Dbmaj7#11" => root pitch class, tones in semitones above the root, slash bass or nil.
  def self.parse(name)
    m = name.to_s.sub('6/9', '69').match(%r{\A([A-G])([b#]?)([^/]*)(?:/([A-G])([b#]?))?\z}) or
      raise ArgumentError, "chord #{name.inspect}: no root"
    bass = m[4] && (NOTE_PC.fetch(m[4]) + ACCIDENTAL.fetch(m[5])) % 12
    { pc: (NOTE_PC.fetch(m[1]) + ACCIDENTAL.fetch(m[2])) % 12, tones: tones(m[3], name), bass: bass }
  end

  # Triads, sixths, sevenths, ninths, elevenths, thirteenths, add9/11/13, sus2/sus4 and
  # the alterations b5 #5 b9 #9 #11 b13. Anything left over is an error, named.
  def self.tones(quality, name)
    s = quality.delete('(),')
    third = 4
    fifth = 7
    seventh = sixth = nil
    extensions = []
    third = 3 if s.sub!(/\A(?:min|mi|-|m(?!aj))/, '')
    if s.sub!(/\Adim/, '')
      third = 3
      fifth = 6
      seventh = 9 if s.start_with?('7')
    end
    fifth = 8 if s.sub!(/\A(?:aug|\+)/, '')
    third = 2 if s.sub!(/sus2/, '')
    third = 5 if s.sub!(/sus4|sus/, '')
    level = 0
    if s.sub!(/\A(?:maj|M)(7|9|11|13)?/, '')
      level = Regexp.last_match(1).to_i
      seventh = 11 if level.positive?
    elsif (digits = s[/\A(?:7|9|11|13)/])
      level = digits.to_i
      seventh ||= 10
      s.sub!(/\A(?:7|9|11|13)/, '')
    elsif s.sub!(/\A69/, '')
      sixth = 9
      extensions << 14
    elsif s.sub!(/\A6/, '')
      sixth = 9
    end
    extensions << 14 if level >= 9
    extensions << 17 if level == 11
    extensions << 21 if level >= 13
    extensions << 14 if s.sub!(/add9/, '')
    extensions << 17 if s.sub!(/add11/, '')
    extensions << 21 if s.sub!(/add13/, '')
    sixth = 9 if s.sub!(/add6/, '')
    if s.sub!(/alt/, '')
      seventh ||= 10
      fifth = nil
      extensions = [13, 20]
    end
    while (alteration = s.slice!(/[b#](?:5|9|11|13)/))
      case alteration
      when 'b5' then fifth = 6
      when '#5' then fifth = 8
      when 'b9' then extensions = extensions.reject { |e| e == 14 } + [13]
      when '#9' then extensions = extensions.reject { |e| e == 14 } + [15]
      when '#11' then extensions = extensions.reject { |e| e == 17 } + [18]
      when 'b13' then extensions = extensions.reject { |e| e == 21 } + [20]
      end
    end
    raise ArgumentError, "chord #{name.inspect}: cannot read #{s.inspect}" unless s.empty?

    ([0, third, fifth, sixth, seventh] + extensions).compact.uniq.sort
  end

  MAX_VOICES = 5   # the bass and four above it
  LOW = 52         # the upper structure sits between these two notes
  HIGH = 84
  MIN_GAP = 2      # neighbours are at least a whole tone apart: no minor second rubs
  CENTRE = 66      # the middle of that register, which the search is gently pulled toward
  PULL = 0.1       # semitones of cost per semitone the voicing sits from the centre

  # The tones above the bass, as pitch classes. The root stays out when the bass already
  # plays it and the chord has more than a triad; when the chord is over the voice cap the
  # perfect fifth goes first, then an altered fifth, then the root. The third or sus tone,
  # the sixth or seventh and every named extension are never dropped.
  def self.upper_pcs(chord)
    bass_pc = chord[:bass] || chord[:pc]
    tones = chord[:tones].dup
    tones -= [0] if tones.size > 3 && bass_pc == chord[:pc]
    [[7], [6, 8], [0]].each do |drop|
      tones -= drop if tones.size > MAX_VOICES - 1
    end
    tones.map { |semi| (chord[:pc] + semi) % 12 }.uniq
  end

  # The note for a pitch class nearest any of the reference notes, inside the register.
  def self.nearest(pc, reference)
    options = (LOW..HIGH).select { |n| n % 12 == pc }
    options.min_by { |n| [reference.map { |r| (n - r).abs }.min, n] }
  end

  def self.valid?(upper)
    upper.first >= LOW && upper.last <= HIGH && upper.each_cons(2).all? { |a, b| b - a >= MIN_GAP }
  end

  # Mean distance each new note moves from its nearest old one, plus the top line's own
  # movement at full weight, plus a small pull toward the middle of the register.
  def self.cost(upper, before)
    pull = PULL * (upper.sum.to_f / upper.size - CENTRE).abs
    return pull if before.empty?

    mean = upper.sum { |n| before.map { |b| (n - b).abs }.min }.to_f / upper.size
    mean + (upper.last - before.last).abs + pull
  end

  # One voicing as MIDI notes, lowest first. Each upper note starts at the one nearest the
  # last chord, then the search tries every octave shift (down, none, up) on every voice and
  # keeps the cheapest set that has no duplicate pitch and no neighbours closer than MIN_GAP.
  def self.voice(name, previous = nil, search: true)
    chord = parse(name)
    bass = 36 + (((chord[:bass] || chord[:pc]) - 36) % 12)
    before = previous ? previous.drop(1) : []
    reference = before.empty? ? [CENTRE] : before
    start = upper_pcs(chord).map { |pc| nearest(pc, reference) }.sort
    return [bass] + apart(start) unless search

    best = nil
    [-12, 0, 12].repeated_permutation(start.size) do |shifts|
      upper = start.zip(shifts).map { |n, s| n + s }.sort
      next unless valid?(upper)

      score = cost(upper, before)
      best = [score, upper] if best.nil? || score < best.first - 1e-9
    end
    [bass] + (best ? best.last : apart(start))
  end

  # A minor second between neighbours is a rub: the upper one goes up an octave, or when
  # that leaves the register the lower one goes down.
  def self.apart(notes)
    out = notes.sort
    12.times do
      i = (1...out.size).find { |k| out[k] - out[k - 1] < MIN_GAP } or break
      out[i] + 12 <= HIGH ? out[i] += 12 : out[i - 1] -= 12
      out.sort!
    end
    out
  end

  def self.hz(midi) = 440.0 * (2.0**((midi - 69) / 12.0))

  # One voicing per chord of a progression, as MIDI notes; each leads from the one before.
  # `transpose` moves every note by that many semitones after voicing (no resampling, the
  # timing is untouched); `wrap` then folds any note still above the audible top down by octaves.
  def self.midi_notes(names, search: true, transpose: 0, wrap: false)
    previous = nil
    names.map do |name|
      previous = voice(name, previous, search:)
      notes = previous.map { |n| n + transpose }
      wrap ? notes.map { |n| fold(n) } : notes
    end
  end

  def self.fold(note)
    note -= 12 while hz(note) > AUDIBLE_TOP_HZ
    note
  end

  def self.freqs(names, search: true, transpose: 0, wrap: false)
    midi_notes(names, search:, transpose:, wrap:).map { |notes| notes.map { |n| hz(n) } }
  end
end

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

# ------------------------------------------------------------------ voices
# Every voice turns a note (a frequency, a length and a level) into samples. The sine voice
# above is the plain one; these are the others, each described by a row of dilla.json.
# Nothing here resamples: a note is synthesised at its own pitch, and a fundamental above
# NYQUIST_SHARE of the sample rate is dropped, never folded back down.
module Voices
  TAU = 2 * Math::PI

  def self.audible?(freq) = freq.positive? && freq <= SAMPLE_RATE * NYQUIST_SHARE

  # A held level 0..1 for an [attack, decay, sustain, release] envelope, linear segments.
  def self.adsr(env, t, gate)
    a, d, s, r = env
    level = lambda do |x|
      if x < a then x / [a, 1e-4].max
      elsif x < a + d then 1.0 - ((1.0 - s) * (x - a) / [d, 1e-4].max)
      else s
      end
    end
    return level.call(t) if t <= gate

    [level.call(gate) * (1.0 - ((t - gate) / [r, 1e-4].max)), 0.0].max
  end

  WAVES = {
    'saw' => ->(p) { (2.0 * p) - 1.0 },
    'pulse' => ->(p) { p < 0.5 ? 1.0 : -1.0 },
    'triangle' => ->(p) { p < 0.5 ? (4.0 * p) - 1.0 : 3.0 - (4.0 * p) }
  }.freeze

  # A four-pole ladder lowpass: each pole moves toward the one before, the last feeds back.
  # The pole coefficient is x / (1 + x), which needs no exponential in the sample loop.
  class Ladder
    def initialize
      @z = [0.0, 0.0, 0.0, 0.0]
    end

    def process(sample, cutoff, resonance)
      x = TAU * cutoff.clamp(20.0, SAMPLE_RATE * 0.45) / SAMPLE_RATE
      g = x / (1.0 + x)
      input = sample - (resonance * 4.0 * @z[3])
      input /= (1.0 + (input.abs * 0.5)) # soft limit on the way in, so the resonance rounds off
      @z[0] += g * (input - @z[0])
      @z[1] += g * (@z[0] - @z[1])
      @z[2] += g * (@z[1] - @z[2])
      @z[3] += g * (@z[2] - @z[3])
    end
  end

  # Detuned saw and pulse oscillators on phase accumulators, a ladder with its own envelope
  # sweeping the cutoff, and an amplitude envelope. Detune is in cents, octaves are integers.
  def self.moog(patch, freq, dur, amp)
    return [] unless audible?(freq)

    release = patch.fetch('amp')[3]
    n = ((dur + release) * SAMPLE_RATE).to_i
    waves = patch.fetch('waves').map { |w| WAVES.fetch(w) }
    incs = patch.fetch('waves').each_index.map do |k|
      freq * (2.0**(patch.fetch('octaves')[k] + (patch.fetch('detune')[k] / 1200.0))) / SAMPLE_RATE
    end
    phases = Array.new(waves.size) { |k| k * 0.13 }
    ladder = Ladder.new
    drive = patch.fetch('drive', 1.0)
    scale = amp * 2.0 / waves.size
    Array.new(n) do |i|
      t = i.to_f / SAMPLE_RATE
      sum = 0.0
      waves.each_index do |k|
        sum += waves[k].call(phases[k])
        phases[k] = (phases[k] + incs[k]) % 1.0
      end
      cutoff = patch.fetch('cutoff') + (patch.fetch('env_amount') * adsr(patch.fetch('filter_env'), t, dur))
      ladder.process(sum * drive * 0.5, cutoff, patch.fetch('resonance')) * adsr(patch.fetch('amp'), t, dur) * scale
    end
  end

  # An electric piano by frequency modulation: a body pair near 1:1 for the mellow tine, a
  # bell pair at 14:1 whose index falls away in a few tenths of a second, a soft hammer click,
  # and a velocity that brightens it. No tremolo and no chorus: nothing moves but the decay.
  def self.rhodes(patch, freq, dur, amp, velocity)
    return [] unless audible?(freq)

    release = patch.fetch('release')
    n = ((dur + release) * SAMPLE_RATE).to_i
    bright = 0.5 + (patch.fetch('velocity_bright') * velocity)
    body = patch.fetch('body_index') * bright
    bell = patch.fetch('bell_index') * bright
    bell_ratio = patch.fetch('bell_ratio')
    bell_k = Math.exp(-1.0 / (patch.fetch('bell_decay') * SAMPLE_RATE))
    body_k = Math.exp(-1.0 / (patch.fetch('body_decay') * SAMPLE_RATE))
    amp_k = Math.exp(-1.0 / (patch.fetch('decay') * SAMPLE_RATE))
    click_k = Math.exp(-1.0 / (0.003 * SAMPLE_RATE))
    rng = Random.new(freq.to_i)
    out_k = Math.exp(-1.0 / (release * SAMPLE_RATE / 4.0))
    carrier = modulator = bell_c = bell_m = 0.0
    body_env = bell_env = amp_env = click_env = hold = 1.0
    cinc = freq / SAMPLE_RATE
    gate_n = (dur * SAMPLE_RATE).to_i
    Array.new(n) do |i|
      m = Math.sin(TAU * modulator)
      b = Math.sin(TAU * bell_m)
      s = Math.sin(TAU * (carrier + (body * body_env * m / TAU))) * 0.8
      s += Math.sin(TAU * (bell_c + (bell * bell_env * b / TAU))) * 0.12 * bell_env
      s += ((rng.rand * 2) - 1) * click_env * patch.fetch('click')
      carrier = (carrier + cinc) % 1.0
      modulator = (modulator + cinc) % 1.0
      bell_c = (bell_c + cinc) % 1.0
      bell_m = (bell_m + (cinc * bell_ratio)) % 1.0
      body_env *= body_k
      bell_env *= bell_k
      click_env *= click_k
      amp_env *= amp_k
      hold *= out_k if i >= gate_n
      s * amp_env * hold * amp * 1.4
    end
  end

  # One hit of a drum-synth voice: a triangle oscillator frequency-modulates a square, both
  # fall in pitch, noise is mixed in, a ladder lowpass and the amplifier each decay. The
  # exponentials are running products, one multiply a sample.
  def self.dfam(patch, freq, dur, amp, decay)
    return [] unless audible?(freq)

    n = [(decay * 4 * SAMPLE_RATE).to_i, (dur * SAMPLE_RATE).to_i].max
    env = patch.fetch('pitch_env')
    pe_k = Math.exp(-1.0 / (env.fetch('seconds') * SAMPLE_RATE))
    ve_k = Math.exp(-1.0 / (decay * SAMPLE_RATE))
    fe_k = Math.exp(-1.0 / (patch.fetch('vcf_decay') * SAMPLE_RATE))
    mix = patch.fetch('mix')
    rng = Random.new(freq.to_i)
    ladder = Ladder.new
    p1 = p2 = 0.0
    pe = ve = fe = 1.0
    Array.new(n) do
      f1 = freq * (1.0 + (env.fetch('depth') * pe))
      tri = WAVES['triangle'].call(p1)
      f2 = f1 * patch.fetch('vco2_ratio') * (1.0 + (patch.fetch('fm') * tri))
      sq = p2 < 0.5 ? 1.0 : -1.0
      p1 = (p1 + (f1 / SAMPLE_RATE)) % 1.0
      p2 = (p2 + (f2 / SAMPLE_RATE)) % 1.0
      src = (tri * mix.fetch('triangle')) + (sq * mix.fetch('square')) + (((rng.rand * 2) - 1) * mix.fetch('noise'))
      cutoff = patch.fetch('cutoff_floor') + (patch.fetch('cutoff') * fe)
      out = ladder.process(src, cutoff, patch.fetch('resonance')) * ve * amp * 2.0
      pe *= pe_k
      ve *= ve_k
      fe *= fe_k
      out
    end
  end

  # The samples for one note of the named voice. `decay` is the drum voice's own, per step.
  def self.note(spec, midi, dur, amp, velocity: 1.0, detune: 0.0, decay: nil)
    freq = Chords.hz(midi)
    amp *= 10.0**(spec.fetch('gain', 0.0) / 20.0)
    case spec.fetch('family')
    when 'sine' then audible?(freq) ? Synth.note(freq, dur, detune:, amp:, release: dur * 0.5) : []
    when 'moog' then moog(spec, freq, dur, amp)
    when 'rhodes' then rhodes(spec, freq, dur, amp, velocity)
    when 'dfam' then dfam(spec, freq, dur, amp, decay || spec.fetch('decay', 0.12))
    else raise ArgumentError, "no voice family #{spec['family'].inspect}"
    end
  end
end

# ------------------------------------------------------------- colour chains
# Sonitex and nasty_vcs, as chains rather than plugins. Sonitex is the 12-bit sampler
# lineage: a drive into a hard band limit, bit and rate reduction, a little hiss and dust,
# a compressor and a limiter. One instance is a colour and three are a sound. nasty_vcs is a
# summing colour, applied wherever things are added, which is what a console does and why
# summed material glues. Both are off unless asked for, and then they only colour.
module Colour
  def self.db(x) = 10.0**(x / 20.0)

  def self.highpass(buf, cutoff)
    a = 1.0 / (1.0 + (2 * Math::PI * cutoff / SAMPLE_RATE))
    y = prev = 0.0
    buf.map do |x|
      y = a * (y + x - prev)
      prev = x
      y
    end
  end

  # A feed-forward compressor: the level follows the signal, over the threshold the gain falls.
  def self.compress(buf, threshold, ratio, attack_ms, release_ms, makeup)
    up = 1.0 - Math.exp(-1.0 / (attack_ms / 1000.0 * SAMPLE_RATE))
    down = 1.0 - Math.exp(-1.0 / (release_ms / 1000.0 * SAMPLE_RATE))
    limit = db(threshold)
    gain_up = db(makeup)
    level = 0.0
    buf.map do |x|
      a = x.abs
      level += (a > level ? up : down) * (a - level)
      over = level > limit ? (limit / level)**(1.0 - (1.0 / ratio)) : 1.0
      x * over * gain_up
    end
  end

  # Sample-rate reduction by `factor` (hold each value) and rounding to `bits` of resolution.
  def self.crush(buf, bits, factor)
    levels = 2.0**(bits - 1)
    held = 0.0
    clock = factor
    buf.map do |x|
      if clock >= factor
        held = (x * levels).round / levels
        clock -= factor
      end
      clock += 1.0
      held
    end
  end

  # Samples under 0.7 pass untouched; above it the level bends toward 1 and never reaches it,
  # so a loud kick stays loud instead of pulling the whole mix down.
  def self.soft_limit(v)
    a = v.abs
    return v if a <= 0.7

    (0.7 + (0.3 * Math.tanh((a - 0.7) / 0.3))) * (v.negative? ? -1 : 1)
  end

  # One pass of the chain with one preset's numbers (see dilla.json).
  def self.sonitex_pass(buf, p, rng)
    drive = p.fetch('dist_drive')
    mix = p.fetch('dist_mix')
    dc = p.fetch('dist_dc')
    pre = FX.lowpass(buf, p.fetch('dist_pre_lp'))
    out = buf.each_index.map do |i|
      wet = Math.tanh((pre[i] * drive) + dc) - Math.tanh(dc)
      (buf[i] * (1.0 - mix)) + (wet * mix / [drive, 1.0].max * 1.2)
    end
    bump = db(p.fetch('head_bump_db')) - 1.0
    low = FX.lowpass(out, p.fetch('head_bump_hz'))
    out = out.each_index.map { |i| out[i] + (bump * low[i]) }
    crushed = FX.lowpass(crush(out, p.fetch('crush_bits'), p.fetch('crush_sr')), p.fetch('crush_post_lp'))
    cm = p.fetch('crush_mix')
    out = out.each_index.map { |i| (out[i] * (1.0 - cm)) + (crushed[i] * cm) }
    out = FX.lowpass(FX.lowpass(out, p.fetch('hf_rolloff')), p.fetch('hf_rolloff'))
    out = highpass(out, p.fetch('lf_rolloff'))
    hiss = p.fetch('hiss_amp')
    pops = p.fetch('pop_rate')
    pop = 0.0
    pop_amp = p.fetch('pop_amp')
    out = out.map do |x|
      pop = (rng.rand < pops ? (rng.rand < 0.5 ? -pop_amp : pop_amp) : pop) * 0.985
      x + (((rng.rand * 2) - 1) * hiss) + (pop * 0.4)
    end
    out = compress(out, p.fetch('out_comp_threshold'), p.fetch('out_comp_ratio'), 12.0, 120.0, p.fetch('out_comp_makeup') - 1.0)
    lim = p.fetch('limit')
    level = p.fetch('level_out')
    out.map { |x| lim * Math.tanh(x / lim) * level }
  end

  def self.sonitex(buf, preset, instances, seed)
    rng = Random.new(seed)
    out = buf
    instances.clamp(1, 3).times { out = sonitex_pass(out, preset, rng) }
    out
  end

  # The summing colour: a soft knee that bends only the peaks, a touch of low warmth, and
  # unity gain for small signals, so summed material glues without getting louder.
  def self.vcs(buf, amount)
    return buf if amount.to_f <= 0.0

    amount = amount.clamp(0.0, 1.0)
    drive = 1.0 + (2.0 * amount)
    warm = FX.lowpass(buf, 180.0)
    buf.each_index.map do |i|
      (Math.tanh((buf[i] + (0.12 * amount * warm[i])) * drive) / drive)
    end
  end
end

# ------------------------------------------------------------------- drums
# Soft, short, synthesised. The noise is seeded, so a seed names a render.
class Drums
  def initialize(seed)
    @rng = Random.new(seed)
  end

  def kick(dur = 0.25)
    n = (dur * SAMPLE_RATE).to_i
    Array.new(n) do |i|
      t = i.to_f / SAMPLE_RATE
      f = 80 * Math.exp(-t * 30) + 40
      Math.sin(2 * Math::PI * f * t) * Math.exp(-t * 12) * 0.9
    end
  end

  def snare(dur = 0.20)
    n = (dur * SAMPLE_RATE).to_i
    Array.new(n) do |i|
      t = i.to_f / SAMPLE_RATE
      noise = @rng.rand * 2 - 1
      tone  = Math.sin(2 * Math::PI * 180 * t)
      (noise * 0.7 + tone * 0.3) * Math.exp(-t * 25) * 0.7
    end
  end

  def hat(dur = 0.06)
    n = (dur * SAMPLE_RATE).to_i
    Array.new(n) do |i|
      t = i.to_f / SAMPLE_RATE
      (@rng.rand * 2 - 1) * Math.exp(-t * 90) * 0.3
    end
  end

  def sounds = { 'kick' => kick, 'snare' => snare, 'hat' => hat }
end

# ---------------------------------------------------------------------- FX
module FX
  def self.lowpass(buf, cutoff)
    return buf if cutoff.nil?
    rc = 1.0 / (2 * Math::PI * cutoff)
    dt = 1.0 / SAMPLE_RATE
    a  = dt / (rc + dt)
    y  = 0.0
    buf.map { |x| y += a * (x - y); y }
  end

  def self.reverb(buf, amount)
    return buf if amount.nil? || amount <= 0
    delays = [0.0297, 0.0371, 0.0411, 0.0437].map { |d| (d * SAMPLE_RATE).to_i }
    gains  = [0.70, 0.65, 0.60, 0.55]
    out = buf.dup
    delays.each_with_index do |d, k|
      i = d
      while i < out.size
        out[i] += out[i - d] * gains[k] * amount
        i += 1
      end
    end
    peak = out.map(&:abs).max
    peak > 1.0 ? out.map { |s| s / peak } : out
  end

  # The profile's texture: lowpass, then reverb.
  def self.apply(buf, profile)
    t = profile['texture'] || {}
    reverb(lowpass(buf, t['lowpass']), t['reverb'])
  end
end

# --------------------------------------------------------------------- arp
# A chord's voicing played one note at a time, lowest voice first. Pure ordering: the
# patterns say which voice sounds on which step, the sequencer says when.
module Arp
  # The voices to cycle through: the voicing, repeated an octave up for each extra octave.
  def self.pool(voices, octaves)
    (0...octaves.clamp(1, 2)).flat_map { |o| voices.map { |n| n + 12 * o } }.uniq.sort
  end

  # `count` notes in the named pattern; nil is a rest. random_seeded draws from the seed, so a
  # seed repeats. broken_pairs alternates a low note with one two places up, thumb_pattern
  # returns to the lowest note between the others, pedal_arp holds it on every fourth step,
  # spread_roll plays the voices once, quickly, and leaves them ringing.
  def self.sequence(pattern, pool, count, seed)
    n = pool.size
    case pattern
    when 'up' then Array.new(count) { |k| pool[k % n] }
    when 'down' then Array.new(count) { |k| pool.reverse[k % n] }
    when 'updown' then cycle(pool + pool[1...-1].to_a.reverse, count)
    when 'converge' then cycle((0...n).map { |i| i.even? ? pool[i / 2] : pool[-1 - (i / 2)] }, count)
    when 'broken_pairs' then Array.new(count) { |k| pool[((k / 2) + (k.odd? ? 2 : 0)) % n] }
    when 'thumb_pattern' then Array.new(count) { |k| k.even? ? pool[0] : pool[1 + ((k / 2) % [n - 1, 1].max)] }
    when 'pedal_arp' then Array.new(count) { |k| (k % 4).zero? ? pool[0] : pool[1 + ((k - (k / 4) - 1) % [n - 1, 1].max)] }
    when 'spread_roll' then Array.new(count) { |k| k < n ? pool[k] : nil }
    when 'random_seeded'
      rng = Random.new(seed)
      Array.new(count) { pool[rng.rand(n)] }
    else raise ArgumentError, "no arp pattern #{pattern.inspect}"
    end
  end

  def self.cycle(list, count) = Array.new(count) { |k| list[k % list.size] }
end

# One arpeggio note: `base` is where its step falls on the grid, `off` how far it leans from
# there (swing and humanize, clamped to MAX_OFFSET), the rest as they sound.
Pluck = Struct.new(:base, :off, :midi, :dur, :gain) # midi is one note, or a chord's notes

module Arp
  # The small modifiers that shape the note stream, applied in the order the arp lists them.
  # `slot` is the length of one arp step in seconds; `peak` the strongest accent gain.
  def self.modify(plucks, name, params, rng, slot:, peak:)
    case name
    when 'euclidean'
      steps = params.fetch('steps', 8)
      pulses = params.fetch('pulses', 5).clamp(1, steps)
      plucks.each_with_index.select { |_, i| ((i * pulses) % steps) < pulses }.map(&:first)
    when 'probability'
      plucks.select { |_| rng.rand <= params.fetch('probability', 1.0) }
    when 'note_repeat'
      count = params.fetch('count', 1).clamp(1, 6)
      plucks.flat_map { |p| split(p, count, slot, 0.72, 0.06) }
    when 'ratchet'
      max = params.fetch('max', 3).clamp(1, 4)
      plucks.flat_map do |p|
        accented = p.gain >= peak * 0.99 && rng.rand < params.fetch('chance', 0.5)
        accented && max > 1 ? split(p, rng.rand(2..max), slot, 0.86, 0.11) : [p]
      end
    when 'humanize'
      ms = params.fetch('ms', 4.0) / 1000.0
      g = params.fetch('gain', 0.06)
      plucks.each do |p|
        p.off += rng.rand(-ms..ms)
        p.gain = (p.gain + rng.rand(-g..g)).clamp(0.0, 1.0)
      end
    when 'grace'
      tones = params.fetch('tones', []).sort # a grace note is the next chord tone below, never a chromatic neighbour
      plucks.flat_map do |p|
        below = Array(p.midi).map { |m| tones.reverse.find { |t| t < m } || m }
        grace = Pluck.new(p.base - [p.dur * 0.18, 0.035].max, p.off, p.midi.is_a?(Array) ? below : below.first, [p.dur * 0.12, 0.018].max, p.gain * params.fetch('gain', 0.3))
        [grace, p]
      end
    else raise ArgumentError, "no arp modifier #{name.inspect}"
    end
  end

  # `count` evenly spaced copies of a note within its slot, each `fade` quieter than the last.
  def self.split(pluck, count, slot, held, fade)
    return [pluck] if count <= 1

    each = slot / count
    Array.new(count) do |i|
      Pluck.new(pluck.base + (each * i), pluck.off, pluck.midi, [each * held, 0.018].max, pluck.gain * (1.0 - (fade * i)))
    end
  end
end

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

# ---------------------------------------------------------------- sequencer
# One groove profile says how the render is played. Everything is in seconds or in
# fractions, all of it scaled by pd_amount (0 is the grid, 1 is the profile, up to 1.5).
#
#   swing         where the second chord of a pair lands (0.5 straight, 0.54 a little late)
#   drum_swing    the same for the off-beat sixteenths, per role: kick, snare, hat
#   offsets       seconds a role sits from the grid: kick, snare, hat, and kick_first
#   pocket        leans in fractions of a sixteenth step, so they follow the tempo: per role
#                 { shift_steps, anchor (steps that lean 0), drift_steps (seeded, per voice and
#                 step in the bar, so every bar leans as the first did) }; a snare off the
#                 backbeat steps takes the ghost entry. A role with no entry keeps its offsets.
#   drunk_amount  0..1, a seeded random nudge on every hit, never past MAX_OFFSET
#   sidechain     { amount, release }: the chords dip on every kick (default: none)
#   texture       { detune, lowpass, reverb }
#   arp, echo     present means on; each overrides the defaults of the same name in the data
class Sequencer
  attr_reader :seed, :pd_amount

  def initialize(data, profile_name:, pd_amount: nil, seed: nil, transpose: 0, wrap: false)
    @data = data
    @transpose = transpose
    @wrap = wrap
    @profile = data['groove_profiles'].fetch(profile_name) { abort "No groove profile: #{profile_name}" }
    @seed = seed || Random.new_seed % 1_000_000
    @pd_amount = (pd_amount || @profile.fetch('pd_amount', 1.0)).to_f.clamp(0.0, 1.5)
  end

  # Unison detune, kept to six cents (a frequency ratio of 0.0035) so the layers stay in tune.
  def detune = [(@profile['texture'] || {}).fetch('detune', 0.0), MAX_DETUNE].min

  # The tempo the profile plays at unless --bpm says otherwise.
  def bpm = @profile.fetch('bpm', 88.0)

  # Chords, each the same length, the odd ones swung late.
  def render_chords(names, bpm, beats, search: true, strum: 0.0)
    beat = 60.0 / bpm
    swing = @profile.fetch('swing', 0.5)
    buf = []
    Chords.freqs(names, search:, transpose: @transpose, wrap: @wrap).each_with_index do |freqs, idx|
      delay = idx.even? ? 0.0 : (swing - 0.5) * beat * @pd_amount
      pad = (delay * SAMPLE_RATE).to_i
      buf.concat(Array.new(pad, 0.0)) if pad > 0
      buf.concat(Synth.chord(freqs, beats * beat, detune: detune, strum:))
    end
    buf
  end

  # The arp settings, or nil when neither a flag nor the profile asks for one. A style names a
  # row of arp.styles (a pattern, a rate in sixteenths, a gate, an octave span); the profile's
  # own keys and then the flags are laid over it.
  def arp_settings(flag, style: nil, rate: nil)
    spec = @profile['arp']
    return nil unless flag || spec || style

    base = (@data['arp'] || {}).reject { |k, _| k == 'styles' }
    name = style || spec&.fetch('style', nil)
    row = name ? (@data.dig('arp', 'styles') || {}).fetch(name) { abort "No arp style: #{name}" } : {}
    settings = base.merge(row).merge((spec || {}).reject { |k, _| k == 'style' })
    settings['style'] = name
    settings['pattern'] = flag if flag.is_a?(String)
    settings['pattern'] ||= settings.fetch('default_pattern')
    settings['rate'] = rate if rate
    abort "No arp pattern: #{settings['pattern']}" unless settings.fetch('patterns').include?(settings['pattern'])
    settings
  end

  # The chord-repeat settings: the whole voicing struck again on the steps of a style from
  # comp.styles. nil unless a flag or the profile asks.
  def comp_settings(flag)
    spec = @profile['repeat']
    return nil unless flag || spec

    base = (@data['comp'] || {}).reject { |k, _| k == 'styles' }
    name = flag.is_a?(String) ? flag : (spec&.fetch('style', nil) || base.fetch('default_style'))
    row = (@data.dig('comp', 'styles') || {}).fetch(name) { abort "No repeat style: #{name}" }
    base.merge(row).merge((spec || {}).reject { |k, _| k == 'style' }).merge('style' => name)
  end

  # The voice that plays the notes: the flag's, else the profile's, else the plain sine stack.
  def voice_spec(flag)
    name = flag || @profile['voice'] || 'sine'
    @data.fetch('voices').fetch(name) { abort "No voice: #{name}" }.merge('name' => name)
  end

  # The Sonitex preset and instance count, or nil when neither a flag nor the profile asks.
  def sonitex_settings(flag, instances: nil)
    spec = @profile['sonitex']
    return nil unless flag || spec

    table = @data.fetch('sonitex')
    name = flag.is_a?(String) ? flag : (spec&.fetch('preset', nil) || table.fetch('default'))
    { 'name' => name, 'preset' => table.fetch('presets').fetch(name) { abort "No sonitex preset: #{name}" },
      'instances' => instances || spec&.fetch('instances', nil) || table.fetch('instances', 1) }
  end

  # The nasty_vcs summing amount, or 0 when off.
  def vcs_amount(flag)
    return flag.to_f if flag.is_a?(Float)

    on = flag || @profile.key?('vcs')
    on ? (@profile['vcs'] || @data.fetch('nasty_vcs').fetch('amount')).to_f : 0.0
  end

  # The colour on the voice bus: Sonitex, then the summing colour.
  def colour(buf, sonitex, vcs)
    buf = Colour.sonitex(buf, sonitex.fetch('preset'), sonitex.fetch('instances'), @seed) if sonitex
    Colour.vcs(buf, vcs)
  end

  # Seconds each voice of a chord waits for the one below it: the flag's milliseconds, the data's when bare.
  def strum(flag)
    return 0.0 unless flag

    (flag == true ? @data.fetch('strum').fetch('ms') : flag) / 1000.0
  end

  # The echo settings with the flags laid over them, or nil when nothing asks for one.
  def echo_settings(flag: nil, mix: nil, feedback: nil, time_ms: nil)
    spec = @profile['echo']
    return nil unless flag || spec

    settings = (@data['echo'] || {}).merge(spec || {})
    settings['heads'] = flag.split(',').map(&:to_i) if flag.is_a?(String)
    abort "No echo heads: #{settings['heads']}" unless settings.fetch('modes').include?(settings['heads'])
    settings['echo_volume'] = mix if mix
    settings['intensity'] = feedback if feedback
    settings['time_ms'] = time_ms if time_ms
    settings
  end

  # The chords one note at a time. Each note starts on its step, late by the profile's swing
  # on the off-beat steps, never moved past MAX_OFFSET; an optional soft pad plays beneath.
  # The notes of every chord as events, before any audio: the arp's one-note steps, or the
  # whole voicing struck on each 'x' of a 16-step pattern. Returns one pluck list per chord.
  def note_events(names, bpm, beats, settings, mode, search: true)
    step = 60.0 / bpm / 4.0
    accent = settings.fetch('accent', [1.0])
    chord_steps = (beats * 4).round
    Chords.midi_notes(names, search:, transpose: @transpose, wrap: @wrap).each_with_index.map do |voices, idx|
      if mode == 'arp'
        rate = settings.fetch('rate', 2).to_f
        pool = Arp.pool(voices, settings.fetch('octaves', 1))
        notes = Arp.sequence(settings.fetch('pattern'), pool, (chord_steps / rate).floor, Zlib.crc32("#{@seed}:#{idx}"))
        plucks = notes.each_with_index.filter_map do |midi, k|
          place((idx * chord_steps) + (k * rate), step, midi, rate * step * settings.fetch('gate', 0.8), accent[k % accent.size]) if midi
        end
        modify(plucks, settings, idx, rate * step, accent.max, pool)
      else
        pattern = settings.fetch('pattern')
        marks = (0...pattern.size).select { |i| pattern[i] == 'x' }
        plucks = []
        (0...chord_steps).step(pattern.size) do |bar|
          marks.each_with_index do |m, j|
            next if bar + m >= chord_steps

            gap = (marks[j + 1] || (pattern.size + marks[0])) - m
            plucks << place((idx * chord_steps) + bar + m, step, voices, gap * step * settings.fetch('gate', 0.5), accent[plucks.size % accent.size])
          end
        end
        modify(plucks, settings, idx, step * 2, accent.max, voices)
      end
    end
  end

  def render_arp(names, bpm, beats, arp, search: true, pad: false, voice: nil)
    buf = Array.new(((((names.size * (beats * 4).round * 60.0 / bpm / 4.0)) + 1.0) * SAMPLE_RATE).to_i, 0.0)
    note_events(names, bpm, beats, arp, 'arp', search:).each { |plucks| sound(buf, plucks, voice || voice_spec(nil)) }
    if pad
      under = render_chords(names, bpm, beats, search:)
      under.each_with_index { |v, i| buf[i] += v * arp.fetch('pad', 0.3) if i < buf.size }
    end
    buf
  end

  # The whole voicing struck again on the steps of a style; a hit lasts the gate share of the
  # distance to the next one.
  def render_repeat(names, bpm, beats, comp, search: true, voice: nil)
    buf = Array.new(((((names.size * (beats * 4).round * 60.0 / bpm / 4.0)) + 1.0) * SAMPLE_RATE).to_i, 0.0)
    note_events(names, bpm, beats, comp, 'repeat', search:).each { |plucks| sound(buf, plucks, voice || voice_spec(nil)) }
    buf
  end

  # A note on its step: the profile's swing leans the off-beat steps late.
  def place(s, step, midi, dur, gain)
    pair = s.round % 4 == 2 ? 2 * step : (s.round.odd? ? step : 0.0)
    Pluck.new(s * step, (@profile.fetch('swing', 0.5) - 0.5) * 2 * pair * @pd_amount, midi, dur, gain)
  end

  def modify(plucks, settings, idx, slot, peak, tones)
    rng = Random.new(Zlib.crc32("#{@seed}:modifiers:#{idx}"))
    settings.fetch('modifiers', []).each do |name|
      plucks = Arp.modify(plucks, name, settings.fetch(name, {}).merge('tones' => tones), rng, slot:, peak:)
    end
    plucks
  end

  # Mix each pluck into the buffer through the voice; a chord's level is shared among its notes.
  def sound(buf, plucks, voice)
    plucks.each do |p|
      notes = Array(p.midi)
      notes.each do |midi|
        samples = Voices.note(voice, midi, p.dur, 0.22 * p.gain / Math.sqrt(notes.size), velocity: p.gain, detune: detune)
        start = [((p.base + p.off.clamp(-MAX_OFFSET, MAX_OFFSET)) * SAMPLE_RATE).to_i, 0].max
        samples.each_with_index { |v, j| buf[start + j] += v if start + j < buf.size }
      end
    end
  end

  # Echo on a buffer, the delay from the settings: milliseconds if given, else a number of beats.
  def echo(buf, settings, bpm, resets: [])
    delay = settings['time_ms'] ? settings['time_ms'] / 1000.0 : settings.fetch('time_beats') * 60.0 / bpm
    out = Echo.process(buf, delay:, heads: settings.fetch('heads'), intensity: settings.fetch('intensity'),
                            volume: settings.fetch('echo_volume'), lowpass: settings['lowpass'],
                            saturation: settings.fetch('saturation', 0.0), reverb: settings.fetch('reverb', 0.0),
                            tail: settings.fetch('tail', 4.0), resets:)
    peak = out.map(&:abs).max
    peak > 1.0 ? out.map { |v| v / peak } : out
  end

  # Where every hit lands, in seconds: the 16-step pattern repeats bar after bar until
  # the chords end. Returns [[role, time]], earliest first.
  def drum_hits(pattern_name, bpm, seconds)
    pattern = @data['drum_patterns'].fetch(pattern_name) { abort "No drum pattern: #{pattern_name}" }
    rng = Random.new(@seed)
    step = 60.0 / bpm / 4.0
    offsets = @profile['offsets'] || {}
    pocket = @profile['pocket']
    swings = @profile['drum_swing'] || {}
    drunk = pattern.fetch('drunk', @profile.fetch('drunk_amount', 0.0)).to_f
    hits = []
    first_kick = true
    (seconds / (step * 16)).ceil.times do |bar|
      16.times do |i|
        pattern.each do |role, row|
          next unless row.is_a?(Array) && row[i].to_i.positive?

          nudge = offsets.fetch(role, 0.0)
          nudge = pocket_lean(pocket, role, i) * step if pocket&.key?(role)
          if role == 'kick' && first_kick
            nudge = offsets.fetch('kick_first', nudge) unless pocket&.key?(role)
            first_kick = false
          end
          nudge += (rng.rand * 2 - 1) * MAX_OFFSET * drunk
          # the off-beat eighth (step 2 of 4) and the odd sixteenths take the swing
          pair = i % 4 == 2 ? 2 * step : (i.odd? ? step : 0.0)
          late = (swings.fetch(role, 0.5) - 0.5) * 2 * pair
          # offset, swing and drunk together never move a hit more than MAX_OFFSET
          moved = ((nudge + late) * @pd_amount).clamp(-MAX_OFFSET, MAX_OFFSET)
          t = ((bar * 16 + i) * step) + moved
          hits << [role, [t, 0.0].max] if t < seconds
        end
      end
    end
    hits.sort_by(&:last)
  end

  # How far a hit leans from its step, in sixteenths (before --groove). The draw belongs to
  # the render seed, the voice and the step in the bar, never the bar, so bars repeat.
  def pocket_lean(pocket, role, step_in_bar)
    spec = pocket.fetch(role)
    ghost = pocket['ghost']
    spec = ghost if ghost && role == 'snare' && !pocket.fetch('backbeat', []).include?(step_in_bar)
    return 0.0 if spec.fetch('anchor', []).include?(step_in_bar)

    draw = Random.new(Zlib.crc32("#{@seed}:#{role}:#{step_in_bar}")).rand * 2 - 1
    spec.fetch('shift_steps', 0.0) + spec.fetch('drift_steps', 0.0) * draw
  end

  # The mix levels in dB: the data's, the profile's over them, the flags over those.
  def mix(flags)
    (@data['mix'] || {}).merge(@profile['mix'] || {}).merge(flags || {}).tap do |levels|
      %w[kick snare clap hat perc chords echo].each { |k| levels[k] ||= 0.0 }
    end
  end

  def scale(buf, db)
    gain = 10.0**(db / 20.0)
    buf.map { |v| v * gain }
  end

  # The drums laid over the chords, each role at its mix level; the kick is added after the
  # duck, so the pump never touches it. With a summing colour the drums are a bus of their
  # own and the sum is coloured again; the sum never exceeds full scale.
  def overlay_drums(chord_buf, hits, levels = {}, vcs = 0.0)
    sounds = Drums.new(@seed).sounds
    drum_bus = vcs.positive? ? Array.new(chord_buf.size, 0.0) : nil
    out = drum_bus ? drum_bus : chord_buf.dup
    hits.each do |role, time|
      start = (time * SAMPLE_RATE).to_i
      gain = 0.8 * (10.0**(levels.fetch(role, 0.0) / 20.0))
      sounds.fetch(role).each_with_index do |s, j|
        idx = start + j
        break if idx >= out.size
        out[idx] += s * gain
      end
    end
    if drum_bus
      drums = Colour.vcs(drum_bus, vcs)
      out = chord_buf.each_index.map { |i| chord_buf[i] + drums[i] }
      out = Colour.vcs(out, vcs * 0.5)
    end
    out.map(&:abs).max > 1.0 ? out.map { |v| Colour.soft_limit(v) } : out
  end

  # The chords duck on every kick: a gain envelope keyed to the hits, not an oscillator.
  def duck(chord_buf, hits)
    sc = @profile['sidechain'] or return chord_buf
    amount = sc.fetch('amount', 0.0) * @pd_amount
    release = sc.fetch('release', 0.15) * SAMPLE_RATE
    return chord_buf if amount.zero?

    gain = Array.new(chord_buf.size, 1.0)
    hits.each do |role, time|
      next unless role == 'kick'

      start = (time * SAMPLE_RATE).to_i
      (0...(release * 4).to_i).each do |n|
        idx = start + n
        break if idx >= gain.size
        g = 1.0 - amount * Math.exp(-n / release)
        gain[idx] = g if g < gain[idx]
      end
    end
    chord_buf.each_with_index.map { |s, i| s * gain[i] }
  end
end

# ------------------------------------------------------------------- MIDI
# A Standard MIDI File, format 0: the chords on channel 1 and the drums on channel 10
# (kick 36, snare 38, hat 42). Times are the same ones the WAV uses.
module MIDI
  PPQN = 480
  DRUM_NOTES = { 'kick' => 36, 'snare' => 38, 'hat' => 42 }.freeze

  def self.vlq(number)
    bytes = [number & 0x7f]
    while (number >>= 7).positive?
      bytes.unshift((number & 0x7f) | 0x80)
    end
    bytes.pack('C*')
  end

  def self.write(path, names, bpm, beats, hits, search: true)
    ticks = ->(seconds) { (seconds * bpm / 60.0 * PPQN).round }
    chord_len = (beats * PPQN).round
    events = []
    Chords.midi_notes(names, search:).each_with_index do |notes, idx|
      notes.each do |n|
        events << [idx * chord_len, 0x90, n, 80]
        events << [(idx + 1) * chord_len, 0x80, n, 0]
      end
    end
    hits.each do |role, time|
      on = ticks.call(time)
      events << [on, 0x99, DRUM_NOTES.fetch(role), 100]
      events << [on + 30, 0x89, DRUM_NOTES.fetch(role), 0]
    end
    track = "\x00\xFF\x51\x03".b + [(60_000_000 / bpm).round].pack('N')[1, 3]
    last = 0
    events.sort_by { |tick, status, *| [tick, status & 0xf0 == 0x80 ? 0 : 1] }.each do |tick, status, note, vel|
      track << vlq(tick - last) << [status, note, vel].pack('C3')
      last = tick
    end
    track << "\x00\xFF\x2F\x00".b
    header = 'MThd'.b + [6, 0, 1, PPQN].pack('Nnnn')
    File.binwrite(path, header + 'MTrk'.b + [track.bytesize].pack('N') + track)
  end
end

# ---------------------------------------------------------------------- CLI
def run(argv)
  options = {}
  OptionParser.new do |o|
    o.banner = 'Usage: ruby dilla.rb [options]'
    o.on('--list', 'List progressions, drum patterns and groove profiles') { options[:list] = true }
    o.on('--progression N', Integer, 'Progression index (see --list)') { |v| options[:prog] = v }
    o.on('--random', 'Random progression and drum pattern (the default groove profile)') { options[:random] = true }
    o.on('--drums NAME', 'Drum pattern name') { |v| options[:drums] = v }
    o.on('--profile NAME', 'Groove profile name') { |v| options[:profile] = v }
    o.on('--groove N', Float, 'pd_amount, 0 to 1.5: how far the profile pulls from the grid') { |v| options[:groove] = v }
    o.on('--bpm N', Float, 'Tempo (default 88)') { |v| options[:bpm] = v }
    o.on('--beats N', Float, 'Beats per chord (default 4)') { |v| options[:beats] = v }
    o.on('--seed N', Integer, 'Seed: the same seed plays the same render') { |v| options[:seed] = v }
    o.on('--out PATH', 'Output WAV path') { |v| options[:out] = v }
    o.on('--midi PATH', 'Also write a Standard MIDI File') { |v| options[:midi] = v }
    o.on('--no-voice-search', 'Voice each chord by nearest tones only, without the octave search') { options[:plain] = true }
    o.on('--arp [PATTERN]', 'Play each chord one note at a time: up, down, updown, converge, random_seeded') { |v| options[:arp] = v || true }
    o.on('--strum [MS]', Float, 'Stagger the notes of each chord, lowest first, by MS milliseconds (default from the data)') { |v| options[:strum] = v || true }
    o.on('--pad', 'A soft sustained pad under the arpeggio') { options[:pad] = true }
    o.on('--echo [HEADS]', 'Tape space echo; heads such as 1 or 1,2 or 1,2,3') { |v| options[:echo] = v || true }
    o.on('--echo-mix N', Float, 'Echo volume against the dry sound') { |v| options[:echo_mix] = v }
    o.on('--echo-feedback N', Float, 'Echo intensity, 0 to 0.9: how much of each repeat comes round again') { |v| options[:echo_feedback] = v }
    o.on('--echo-time MS', Float, 'Echo base delay in milliseconds (default a dotted eighth)') { |v| options[:echo_time] = v }
    o.on('--play', '--endless', 'Never stop: render the next progression while this one plays') { options[:play] = true }
    o.on('--player CMD', 'The command that plays a wav (default afplay, else ffplay)') { |v| options[:player] = v }
    o.on('--passes N', Integer, 'With --play, stop after N progressions') { |v| options[:passes] = v }
    o.on('--voice NAME', 'The voice that plays the notes (see dilla.json): sine, moog_*, rhodes_*, dfam') { |v| options[:voice] = v }
    o.on('--repeat [STYLE]', '--comp [STYLE]', 'Strike the whole chord again on the steps of a style instead of arpeggiating') { |v| options[:repeat] = v || true }
    o.on('--mode MODE', 'arp, repeat or pad: force how the chords are played') { |v| options[:mode] = v }
    o.on('--arp-rate N', 'Sixteenths per arp note: 2 eighth, 3 dotted eighth, 4 quarter, 6, 8; 3T for triplets') { |v| options[:arp_rate] = v }
    o.on('--arp-style NAME', 'A row of arp.styles in dilla.json') { |v| options[:arp_style] = v }
    o.on('--sonitex [PRESET]', 'The 12-bit sampler colour chain on the voice bus') { |v| options[:sonitex] = v || true }
    o.on('--sonitex-instances N', Integer, 'Run it 1 to 3 times: one is a colour, three are a sound') { |v| options[:sonitex_instances] = v }
    o.on('--vcs [AMOUNT]', Float, 'The summing colour, 0 to 1, on each bus and the master') { |v| options[:vcs] = v || true }
    o.on('--transpose N', Integer, 'Move every note N semitones before synthesis; tempo and echo timing stay') { |v| options[:transpose] = v }
    o.on('--octaves N', Integer, 'Sugar for --transpose 12*N') { |v| options[:transpose] = 12 * v }
    o.on('--transpose-wrap', 'Fold any note still above 14 kHz down by octaves') { options[:wrap] = true }
    o.on('--kick-db N', Float, 'Kick level in dB (default from the data)') { |v| (options[:mix] ||= {})['kick'] = v }
    o.on('--snare-db N', Float, 'Snare and clap level in dB') { |v| (options[:mix] ||= {}).merge!('snare' => v, 'clap' => v) }
    o.on('--hat-db N', Float, 'Hat level in dB') { |v| (options[:mix] ||= {})['hat'] = v }
    o.on('--chords-db N', Float, 'Chord and arp level in dB when drums play') { |v| (options[:mix] ||= {})['chords'] = v }
    o.on('--quick', 'Render the first progression as a smoke test') { options[:quick] = true }
  end.parse!(argv)

  data = JSON.parse(File.read(File.join(__dir__, 'dilla.json')))
  progressions = data.fetch('progressions')

  if options[:play]
    play_forever(data, options)
  elsif options[:list] || (options[:prog].nil? && !options[:random] && !options[:quick])
    puts 'Progressions:'
    progressions.each_with_index { |chords, i| puts format('%4d  %s', i, chords.join(' ')) }
    puts
    puts "Drum patterns: #{data['drum_patterns'].keys.join(', ')}"
    puts "Groove profiles: #{data['groove_profiles'].keys.join(', ')}"
  else
    render(data, options)
  end
end

# How the chords are played: the flags, else what the profile carries, else a held pad.
def play_mode(options, seq)
  return options[:mode] if options[:mode]
  return 'repeat' if options[:repeat] || (!options[:arp] && seq.comp_settings(nil))
  return 'arp' if options[:arp] || options[:arp_style] || seq.arp_settings(nil)

  'pad'
end

def parse_rate(text)
  return nil unless text

  text.to_s.match(/\A(\d+(?:\.\d+)?)(T?)\z/) or abort "Bad --arp-rate: #{text}"
  Regexp.last_match(2).empty? ? Regexp.last_match(1).to_f : Regexp.last_match(1).to_f * 2 / 3
end

# One render: the options name a progression or let the seed choose one. Returns the output path.
def render(data, options)
  progressions = data.fetch('progressions')
  seed = options[:seed] || Random.new_seed % 1_000_000
  pick = Random.new(seed)
  index = options[:quick] ? 0 : (options[:prog] || pick.rand(progressions.size))
  names = progressions.fetch(index) { abort "No progression: #{index}" }
  drums = options[:drums] || (options[:random] ? data['drum_patterns'].keys.sample(random: pick) : nil)
  profile = options[:profile] || data.fetch('default_profile')

  seq = Sequencer.new(data, profile_name: profile, pd_amount: options[:groove], seed: seed,
                            transpose: options[:transpose] || 0, wrap: options[:wrap])
  bpm = options[:bpm] || seq.bpm
  beats = options[:beats] || 4.0
  voice = seq.voice_spec(options[:voice])
  search = !options[:plain]
  mode = play_mode(options, seq)
  warn_past_nyquist(names, search, options)
  buf =
    case mode
    when 'arp'
      arp = seq.arp_settings(options[:arp], style: options[:arp_style], rate: parse_rate(options[:arp_rate]))
      seq.render_arp(names, bpm, beats, arp, search:, pad: options[:pad], voice:)
    when 'repeat'
      seq.render_repeat(names, bpm, beats, seq.comp_settings(options[:repeat] || true), search:, voice:)
    else
      seq.render_chords(names, bpm, beats, search:, strum: seq.strum(options[:strum]))
    end
  vcs = seq.vcs_amount(options[:vcs])
  buf = seq.colour(buf, seq.sonitex_settings(options[:sonitex], instances: options[:sonitex_instances]), vcs)
  echo = seq.echo_settings(flag: options[:echo], mix: options[:echo_mix], feedback: options[:echo_feedback], time_ms: options[:echo_time])
  buf = seq.echo(buf, echo, bpm, resets: (1...names.size).map { |i| (i * beats * 60.0 / bpm * SAMPLE_RATE).round }) if echo
  seconds = buf.size / SAMPLE_RATE.to_f
  hits = drums ? seq.drum_hits(drums, bpm, seconds) : []
  levels = seq.mix(options[:mix])
  buf = seq.scale(buf, levels.fetch('chords')) unless hits.empty?
  buf = seq.duck(buf, hits)
  buf = FX.apply(buf, data['groove_profiles'].fetch(profile))
  buf = seq.overlay_drums(buf, hits, levels, vcs) if drums

  out = options[:out] || (options[:quick] ? 'out/quick.wav' : "out/progression_#{index}#{drums ? "_#{drums}" : ''}.wav")
  FileUtils.mkdir_p(File.dirname(out))
  WAV.write(out, buf)
  if options[:midi]
    FileUtils.mkdir_p(File.dirname(options[:midi]))
    MIDI.write(options[:midi], names, bpm, beats, hits, search:)
  end
  puts "Wrote #{out} (#{seconds.round(2)}s) progression #{index}: #{names.join(' ')}"
  puts "  drums=#{drums || 'none'} profile=#{profile} mode=#{mode} voice=#{voice['name']} groove=#{seq.pd_amount} bpm=#{bpm} seed=#{seed}"
  out
end

# A transposed note above the sample rate's limit cannot be played; say so rather than fake it.
def warn_past_nyquist(names, search, options)
  return unless options[:transpose]&.nonzero?

  notes = Chords.midi_notes(names, search:, transpose: options[:transpose], wrap: options[:wrap]).flatten
  over = notes.count { |n| !Voices.audible?(Chords.hz(n)) }
  return if over.zero?

  warn format('warning: %<over>d of %<all>d notes are above %<limit>d Hz and are dropped (silence); --transpose-wrap folds them down',
              over:, all: notes.size, limit: SAMPLE_RATE * NYQUIST_SHARE)
end

# The player command for a wav: --player, else afplay on a Mac, else ffplay.
def player_command(options)
  return Shellwords.split(options[:player]) if options[:player]

  RUBY_PLATFORM.include?('darwin') ? ['afplay'] : %w[ffplay -nodisp -autoexit -loglevel quiet]
end

# A shuffle bag: every item comes out once before any comes out again, and the first of a new
# bag is never the last of the old one. The state is a plain hash, so a restart can go on.
class Bag
  def initialize(items, rng, state = nil)
    @items = items
    @rng = rng
    @remaining = (state&.fetch('remaining', nil) || []).select { |i| items.include?(i) }
    @last = state&.fetch('last', nil)
  end

  def draw
    if @remaining.empty?
      @remaining = @items.shuffle(random: @rng)
      @remaining.rotate! if @remaining.size > 1 && @remaining.first == @last
    end
    @last = @remaining.shift
  end

  def position = "#{@items.size - @remaining.size}/#{@items.size}"

  def to_h = { 'remaining' => @remaining, 'last' => @last }
end

# What each pass draws, every kind from its own bag: the progression from the whole array, the
# mode, the arp or repeat style, the voice family, a patch of that family, the treatment.
class Playlist
  MODES = %w[arp repeat pad].freeze

  def initialize(data, rng, state = {})
    @data = data
    @rng = rng
    @state = state
    @bags = {}
  end

  def bag(key, items)
    @bags[key] ||= Bag.new(items, @rng, @state[key])
  end

  def voices_by_family = @data.fetch('voices').group_by { |_, v| v.fetch('family') }.transform_values { |rows| rows.map(&:first) }

  def draw(fixed = {})
    index = bag('progressions', (0...@data.fetch('progressions').size).to_a).draw
    position = @bags['progressions'].position
    mode = fixed[:mode] || bag('modes', MODES).draw
    style = case mode
            when 'arp' then bag('styles:arp', @data.dig('arp', 'play_styles')).draw
            when 'repeat' then bag('styles:repeat', @data.fetch('comp').fetch('styles').keys).draw
            end
    families = voices_by_family
    voice = fixed[:voice] || begin
      family = bag('families', families.keys.sort).draw
      bag("patches:#{family}", families.fetch(family).sort).draw
    end
    profile = fixed[:profile] || bag('profiles', @data.fetch('play_profiles')).draw
    { prog: index, position:, mode:, style:, voice:, profile: }
  end

  def to_h = @bags.transform_values(&:to_h)
end

# Never stops: each pass draws from the playlist, renders while the one before plays, and
# plays it when that ends. Two files alternate, so the one being played is never the one being
# written; the bags are saved beside them, so a restart goes on with the cycle.
def play_forever(data, options)
  rng = Random.new(options[:seed] || Random.new_seed)
  dir = options[:out] ? File.dirname(options[:out]) : 'out/play'
  FileUtils.mkdir_p(dir)
  state_path = File.join(dir, 'play_state.json')
  state = (JSON.parse(File.read(state_path)) rescue {})
  playlist = Playlist.new(data, rng, state)
  command = player_command(options)
  pid = nil
  trap('INT') { pid && Process.kill('TERM', pid); exit }
  trap('TERM') { pid && Process.kill('TERM', pid); exit }
  (1..(options[:passes] || Float::INFINITY)).each do |pass|
    pick = playlist.draw(mode: options[:mode], voice: options[:voice], profile: options[:profile])
    pass_options = options.merge(prog: pick[:prog], seed: rng.rand(1_000_000), profile: pick[:profile], voice: pick[:voice],
                                 mode: pick[:mode], random: false, quick: false, play: false,
                                 out: File.join(dir, "play_#{pass.odd? ? 'a' : 'b'}.wav"))
    pass_options[:arp_style] = options[:arp_style] || pick[:style] if pick[:mode] == 'arp'
    pass_options[:repeat] = options[:repeat] || pick[:style] if pick[:mode] == 'repeat'
    profile_drums = data['groove_profiles'].fetch(pick[:profile])['drums']
    pass_options[:drums] = options[:drums] || profile_drums
    puts "pass #{pass}: progression #{pick[:prog]} (#{pick[:position]}) mode=#{pick[:mode]} style=#{pick[:style] || '-'} voice=#{pick[:voice]} profile=#{pick[:profile]}"
    path = render(data, pass_options)
    File.write(state_path, JSON.generate(playlist.to_h))
    Process.wait(pid) if pid
    pid = Process.spawn(*command, path)
  end
  Process.wait(pid) if pid
end

run(ARGV) if $PROGRAM_NAME == __FILE__
