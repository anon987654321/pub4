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

SAMPLE_RATE = 44_100
MAX_OFFSET = 0.035 # seconds: no role is ever moved further than this from its place

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
  def self.midi_notes(names, search: true)
    previous = nil
    names.map { |name| previous = voice(name, previous, search:) }
  end

  def self.freqs(names, search: true) = midi_notes(names, search:).map { |notes| notes.map { |n| hz(n) } }
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
  def self.chord(freqs, dur, detune: 0.0)
    n = (dur * SAMPLE_RATE).to_i
    buf = Array.new(n, 0.0)
    freqs.each_with_index do |f, idx|
      d = detune * (idx.even? ? 1 : -1)
      note_buf = note(f, dur, detune: d, amp: 1.0 / freqs.size)
      note_buf.each_with_index { |s, i| buf[i] += s if i < n }
    end
    buf
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

  # `count` notes in the named pattern. random_seeded draws from the seed, so a seed repeats.
  def self.sequence(pattern, pool, count, seed)
    cycle =
      case pattern
      when 'up' then pool
      when 'down' then pool.reverse
      when 'updown' then pool + pool[1...-1].to_a.reverse
      when 'converge' then (0...pool.size).map { |i| i.even? ? pool[i / 2] : pool[-1 - i / 2] }
      when 'random_seeded' then nil
      else raise ArgumentError, "no arp pattern #{pattern.inspect}"
      end
    return Array.new(count) { |k| cycle[k % cycle.size] } if cycle

    rng = Random.new(seed)
    Array.new(count) { pool[rng.rand(pool.size)] }
  end
end

# -------------------------------------------------------------- tape echo
# A space echo: three playback heads read one loop at 1x, 2x and 3x the base delay. The
# heads in use are summed, darkened by a lowpass and a mild saturation, and fed back, so each
# repeat is quieter and duller than the last. No modulation: the tape runs true.
module Echo
  MAX_INTENSITY = 0.9 # feedback never reaches one, so the loop cannot run away

  def self.process(buf, delay:, heads: [1, 2], intensity: 0.5, volume: 0.45, lowpass: 3200, saturation: 0.35, reverb: 0.0)
    intensity = intensity.to_f.clamp(0.0, MAX_INTENSITY)
    d = [(delay * SAMPLE_RATE).round, 1].max
    ring = Array.new((heads.max * d) + 1, 0.0)
    tail = [heads.max * d * 6, SAMPLE_RATE * 4].min
    cutoff = lowpass ? 1.0 / ((2 * Math::PI * lowpass * (1.0 / SAMPLE_RATE)) + 1.0) : 0.0
    drive = 1.0 + (2.0 * saturation)
    share = 1.0 / heads.size
    y = 0.0
    wet = Array.new(buf.size + tail, 0.0)
    wet.each_index do |n|
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

  def initialize(data, profile_name:, pd_amount: nil, seed: nil)
    @data = data
    @profile = data['groove_profiles'].fetch(profile_name) { abort "No groove profile: #{profile_name}" }
    @seed = seed || Random.new_seed % 1_000_000
    @pd_amount = (pd_amount || @profile.fetch('pd_amount', 1.0)).to_f.clamp(0.0, 1.5)
  end

  def detune = (@profile['texture'] || {}).fetch('detune', 0.0)

  # Chords, each the same length, the odd ones swung late.
  def render_chords(names, bpm, beats, search: true)
    beat = 60.0 / bpm
    swing = @profile.fetch('swing', 0.5)
    buf = []
    Chords.freqs(names, search:).each_with_index do |freqs, idx|
      delay = idx.even? ? 0.0 : (swing - 0.5) * beat * @pd_amount
      pad = (delay * SAMPLE_RATE).to_i
      buf.concat(Array.new(pad, 0.0)) if pad > 0
      buf.concat(Synth.chord(freqs, beats * beat, detune: detune))
    end
    buf
  end

  # The arp settings, or nil when neither the flag nor the profile asks for one.
  def arp_settings(flag)
    spec = @profile['arp']
    return nil unless flag || spec

    settings = (@data['arp'] || {}).merge(spec || {})
    settings['pattern'] = flag if flag.is_a?(String)
    settings['pattern'] ||= settings.fetch('default_pattern')
    abort "No arp pattern: #{settings['pattern']}" unless settings.fetch('patterns').include?(settings['pattern'])
    settings
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
  def render_arp(names, bpm, beats, arp, search: true, pad: false)
    beat = 60.0 / bpm
    step = beat / 4.0
    rate = arp.fetch('rate', 2)
    gate = arp.fetch('gate', 0.8)
    accent = arp.fetch('accent', [1.0])
    swing = @profile.fetch('swing', 0.5)
    chord_steps = (beats * 4).round
    total = names.size * chord_steps * step
    buf = Array.new(((total + 1.0) * SAMPLE_RATE).to_i, 0.0)
    Chords.midi_notes(names, search:).each_with_index do |voices, idx|
      pool = Arp.pool(voices, arp.fetch('octaves', 1))
      count = chord_steps / rate
      notes = Arp.sequence(arp.fetch('pattern'), pool, count, Zlib.crc32("#{@seed}:#{idx}"))
      notes.each_with_index do |midi, k|
        s = (idx * chord_steps) + (k * rate)
        pair = s % 4 == 2 ? 2 * step : (s.odd? ? step : 0.0)
        late = (((swing - 0.5) * 2 * pair) * @pd_amount).clamp(-MAX_OFFSET, MAX_OFFSET)
        dur = rate * step * gate
        samples = Synth.note(Chords.hz(midi), dur, detune: detune, amp: 0.22 * accent[k % accent.size], release: dur * 0.5)
        start = (((s * step) + late) * SAMPLE_RATE).to_i
        samples.each_with_index { |v, j| buf[start + j] += v if start + j < buf.size }
      end
    end
    if pad
      under = render_chords(names, bpm, beats, search:)
      under.each_with_index { |v, i| buf[i] += v * arp.fetch('pad', 0.3) if i < buf.size }
    end
    buf
  end

  # Echo on a buffer, the delay from the settings: milliseconds if given, else a number of beats.
  def echo(buf, settings, bpm)
    delay = settings['time_ms'] ? settings['time_ms'] / 1000.0 : settings.fetch('time_beats') * 60.0 / bpm
    out = Echo.process(buf, delay:, heads: settings.fetch('heads'), intensity: settings.fetch('intensity'),
                            volume: settings.fetch('echo_volume'), lowpass: settings['lowpass'],
                            saturation: settings.fetch('saturation', 0.0), reverb: settings.fetch('reverb', 0.0))
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

  def overlay_drums(chord_buf, hits)
    out = chord_buf.dup
    sounds = Drums.new(@seed).sounds
    hits.each do |role, time|
      start = (time * SAMPLE_RATE).to_i
      sounds.fetch(role).each_with_index do |s, j|
        idx = start + j
        break if idx >= out.size
        out[idx] += s * 0.8
      end
    end
    peak = out.map(&:abs).max
    peak > 1.0 ? out.map { |s| s / peak } : out
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
    o.on('--pad', 'A soft sustained pad under the arpeggio') { options[:pad] = true }
    o.on('--echo [HEADS]', 'Tape space echo; heads such as 1 or 1,2 or 1,2,3') { |v| options[:echo] = v || true }
    o.on('--echo-mix N', Float, 'Echo volume against the dry sound') { |v| options[:echo_mix] = v }
    o.on('--echo-feedback N', Float, 'Echo intensity, 0 to 0.9: how much of each repeat comes round again') { |v| options[:echo_feedback] = v }
    o.on('--echo-time MS', Float, 'Echo base delay in milliseconds (default a dotted eighth)') { |v| options[:echo_time] = v }
    o.on('--quick', 'Render the first progression as a smoke test') { options[:quick] = true }
  end.parse!(argv)

  data = JSON.parse(File.read(File.join(__dir__, 'dilla.json')))
  progressions = data.fetch('progressions')

  if options[:list] || (options[:prog].nil? && !options[:random] && !options[:quick])
    puts 'Progressions:'
    progressions.each_with_index { |chords, i| puts format('%4d  %s', i, chords.join(' ')) }
    puts
    puts "Drum patterns: #{data['drum_patterns'].keys.join(', ')}"
    puts "Groove profiles: #{data['groove_profiles'].keys.join(', ')}"
    return
  end

  seed = options[:seed] || Random.new_seed % 1_000_000
  pick = Random.new(seed)
  index = options[:quick] ? 0 : (options[:prog] || pick.rand(progressions.size))
  names = progressions.fetch(index) { abort "No progression: #{index}" }
  drums = options[:drums] || (options[:random] ? data['drum_patterns'].keys.sample(random: pick) : nil)
  profile = options[:profile] || data.fetch('default_profile')
  bpm = options[:bpm] || 88.0
  beats = options[:beats] || 4.0

  seq = Sequencer.new(data, profile_name: profile, pd_amount: options[:groove], seed: seed)
  arp = seq.arp_settings(options[:arp])
  buf = arp ? seq.render_arp(names, bpm, beats, arp, search: !options[:plain], pad: options[:pad]) : seq.render_chords(names, bpm, beats, search: !options[:plain])
  echo = seq.echo_settings(flag: options[:echo], mix: options[:echo_mix], feedback: options[:echo_feedback], time_ms: options[:echo_time])
  buf = seq.echo(buf, echo, bpm) if echo
  seconds = buf.size / SAMPLE_RATE.to_f
  hits = drums ? seq.drum_hits(drums, bpm, seconds) : []
  buf = seq.duck(buf, hits)
  buf = FX.apply(buf, data['groove_profiles'].fetch(profile))
  buf = seq.overlay_drums(buf, hits) if drums

  out = options[:out] || (options[:quick] ? 'out/quick.wav' : "out/progression_#{index}#{drums ? "_#{drums}" : ''}.wav")
  FileUtils.mkdir_p(File.dirname(out))
  WAV.write(out, buf)
  if options[:midi]
    FileUtils.mkdir_p(File.dirname(options[:midi]))
    MIDI.write(options[:midi], names, bpm, beats, hits, search: !options[:plain])
  end
  puts "Wrote #{out} (#{seconds.round(2)}s) progression #{index}: #{names.join(' ')}"
  puts "  drums=#{drums || 'none'} profile=#{profile} groove=#{seq.pd_amount} bpm=#{bpm} seed=#{seed}"
end

run(ARGV) if $PROGRAM_NAME == __FILE__
