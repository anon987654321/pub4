#!/usr/bin/env ruby
# frozen_string_literal: true

############################################################################
# ARCHIVED 2026-07-26: this is a standalone, unrelated jazz-hop/dark-techno
# experiment, not the Dilla engine (that's ../dilla.rb).
# It was dropped into STUDIO/dilla/dilla.rb by the MASTER/tools -> studio
# extraction (687c07a43) and, because ScriptDispatch resolves media tools by
# STUDIO/<tool>/<tool>.rb convention, silently hijacked every chat-driven
# "make a beat" request (MediaIntent -> ScriptDispatch tool: "dilla") into
# this file instead of the real engine. Moved here so the filename no longer
# collides; kept rather than deleted since every rendered take here failed
# review, but the DSP work (PolyBLEP osc, RBJ biquad EQ, etc.) may still be
# salvageable. Standalone, does not require anything under STUDIO/dilla/lib.
############################################################################
#
# DILLA.RB — merged jazz-hop (hiphop mode) + dark techno (techno mode)
# generator. Single file, two modes, dispatched by the first ARGV token.
#
#   ruby hiphop_techno_experiment.rb hiphop [options]   # see HiphopTrackBuilder / --help
#   ruby hiphop_techno_experiment.rb techno [options]   # see TechnoTrackBuilder / --help
#
# STATUS FOR EXTERNAL REVIEWERS (read this before judging the code)
# ---------------------------------------------------------------------
# The author (an LLM, Claude) CANNOT HEAR AUDIO. Every engineering
# decision below was made from DSP theory, spectrogram visual inspection
# (sox's `spectrogram` effect, viewed as an image), and a human's verbal
# descriptions of what was wrong — never direct listening verification on
# the author's end. Bottom-up isolated tests (bare tone + plain chords,
# then + drums, then + one real instrument voice) were confirmed good by
# the human at each small step. Every full-mix render (all instruments +
# drums + mastering combined) was rejected by ear ("harsh", "trash",
# "sucks") despite each individual piece checking out theoretically and
# despite finding and fixing several real, confirmed bugs along the way:
#   - naive (aliasing) sawtooth oscillators -> fixed with PolyBLEP (techno mode)
#   - repeated identical distortion stages compounding harshness -> fixed
#     by de-stacking to one oversampled pass (techno mode)
#   - an additive-bandpass "peaking EQ" hack that rings/phases -> replaced
#     with the real RBJ biquad peaking formula
#   - a genuine voicing bug: a chord's 3rd and #9 sat a half-step apart in
#     the same register (real dissonance, not "dark color") -> fixed
#   - CONFIRMED VIA SPECTROGRAM: the ported mastering `compand` curves
#     (upward-expansion type, tuned for real recordings with a natural
#     tape/room noise floor around -70..-55dB) were instead grabbing this
#     engine's pristine digital silence / quantization floor and blowing
#     it into audible broadband hiss — isolated and confirmed on a single
#     clean kick hit, fixed by switching to downward-only compressor
#     curves. Full-mix verdict did not measurably improve after this fix,
#     meaning the remaining "sounds bad" complaint is NOT fully explained
#     by any bug found so far.
# hiphop mode was rebuilt late in the process to shell out to real `sox`
# synthesis + effects (ported from a sibling project, pub3/multimedia/
# dilla/lib/synthesis.rb and dilla_data.json) instead of hand-rolled Ruby
# DSP, on the theory that SoX's mature chorus/reverb/compand implementations
# would outperform hand-rolled oscillators. techno mode was NOT migrated to
# this SoX approach and still uses the earlier hand-rolled Ruby DSP
# (PolyBLEP saw, hand-rolled Freeverb, a from-scratch "Sonitex"/"NastyVCS"
# emulation). This inconsistency is itself worth a reviewer's attention.
#
# TECHNICAL CONSTRAINT SPEC (provided by the user, sourced from external
# LLM research on why AI-generated Dilla/FlyLo-style audio tends to fail)
# vs. THIS IMPLEMENTATION'S actual status against each constraint:
#
#   1. Micro-timing: per-instrument offsets + Gaussian (not uniform) jitter
#      + slow phrase-level drift, NOT a single global swing percentage.
#      STATUS: implemented (see Groove module, hiphop mode only). Our
#      Gaussian sigma/outlier-rate were tuned by feel, not fitted to the
#      spec's exact "80% within ±3ms, 5% within ±10-15ms" distribution —
#      a reviewer should check Groove::DEPTH_MS and the 3.5x outlier
#      multiplier against that target explicitly.
#      techno mode has no equivalent per-instrument groove at all — it
#      only has a global tension curve.
#
#   2. Voicing/voice-leading: bass restricted to root/5th in 30-120Hz;
#      chord instruments must never voice the root as the lowest note;
#      avoid intervals <P4 in the bass register; close intervals up top;
#      70%+ of voice movement by step, not leap; real-cents oscillator
#      detuning.
#      STATUS: partially implemented. Theory.spread_voicing/quartal_voicing
#      already drop the root from the upper structure by construction (the
#      bass note is rendered as a separate instrument), so "root never
#      lowest in the chord voicing" holds structurally. refine_voice_leading!
#      does common-tone-lock + parallel-5th/8ve avoidance, which is a
#      DIFFERENT criterion than the spec's "70% stepwise motion" — not
#      measured or enforced against that exact threshold. Oscillator
#      detuning is real (SoxVoice saws use literal cent-ratio multipliers
#      like freq*1.0046). The bass voice (SoxVoice.sub_bass / minimoog) has
#      NO explicit 30-120Hz bandpass enforcement — a reviewer should add
#      one if this matters (`highpass 30 lowpass 120` in the sox chain).
#
#   3. Spectral allocation (strict per-instrument frequency slots, dynamic
#      ducking of the 400Hz-1kHz zone on snare hits, phase-correlation
#      checks below 100Hz): NOT IMPLEMENTED. There is a broad kick-vs-bass
#      sidechain duck (Texture.sidechain_duck!, techno mode only) but no
#      general spectral-slot EQ carving, no dynamic snare-triggered ducking
#      of the harmony bed, and no phase-correlation analysis anywhere. This
#      is the single largest unimplemented section of the spec.
#
#   4. Envelope engineering (kick attack 1-3ms/decay 150-250ms fully
#      returning to zero; ghost notes as a separate, quieter/shorter
#      envelope; slow pad attack 50-200ms to let transients cut through
#      without sidechaining): PARTIALLY implemented — SoxDrums.kick/snare
#      use short (~0.001s) attacks and fades that return to silence by
#      design, but the exact ms targets above were never explicitly
#      verified against sox's `fade`/`synth` timing. Ghost notes exist
#      (hiphop mode, quieter snare re-hits) but don't use a distinctly
#      shorter/different envelope shape, lower gain. Pad attack times
#      vary per SoxVoice function (rhodes ~10ms, cs80/ambient much slower)
#      but were not tuned specifically to "let transients cut through."
#
#   5. Sample manipulation (pitch/time-stretch artifacts as a deliberate
#      aesthetic, bitcrushing samples specifically): N/A as implemented —
#      this engine synthesizes from oscillators/noise, it does not sample
#      real audio, so this section of the spec doesn't apply to the current
#      architecture. (A separate, unmerged experiment earlier in this
#      project's history did chop/pitch a real vocal-group recording via
#      yt-dlp+ffmpeg as an optional pad texture; that path is not wired
#      into this file.)
#
#   6. Automated critic/loss-function scoring (groove correlation penalty,
#      mud-zone energy penalty, crest-factor penalty, harmonic-clash
#      penalty): NOT IMPLEMENTED. No automated self-assessment exists;
#      the only real assessment loop in this project was a human listening
#      and a small number of spectrogram visual inspections done manually.
#      A reviewer building an automated critic against this engine's
#      output would be adding entirely new capability, not fixing a bug.
#
#   7. Hardware-emulation profiles (SP-1200 12-bit/26.04kHz aliasing, MPC
#      SDE-3000-style delay smear): PARTIALLY implemented — hiphop mode's
#      `sp1200_authentic` SoxMaster chain does resample to 26040Hz and
#      recompand/overdrive to approximate SP-1200 degradation (see the
#      dilla_data.json-sourced chain), but there is no MPC-3000/SDE-3000
#      delay-smear emulation anywhere, and techno mode's "Sonitex" hardware
#      emulation is a hand-rolled approximation of a specific VST
#      (Tone Projects Sonitex STX-1260), not the hardware units named here.
#
# In short: this file is architecturally sound and contains several
# genuinely-confirmed bug fixes, but the core open question — why full-mix
# renders still sound bad to a human ear despite that — is UNRESOLVED, and
# section 3 (spectral allocation) above is the most likely place a
# reviewer should look next, since it's the largest fully-unimplemented
# gap between the stated constraints and this code.
############################################################################

require 'optparse'
require 'fileutils'
require 'tmpdir'

SAMPLE_RATE = 44_100
STEPS_PER_BAR = 16

unless system('which sox > /dev/null 2>&1')
  warn 'This engine requires the `sox` binary. Install with: brew install sox'
  exit 1
end

# ===========================================================================
# SHARED THEORY (hiphop mode's harmonic engine; techno mode uses its own
# modal system below since it deliberately has no functional harmony)
# ===========================================================================

# ---------------------------------------------------------------------------
# Theory: extended chords, real progressions, spread/quartal voicings,
# voice-led bass, common-tone/parallel-5th voice-leading refinement.
# Confirmed against a bare sine tone before any instrument/effects work
# began — this layer was never the source of the unresolved "sounds bad"
# complaint described above.
# ---------------------------------------------------------------------------
module Theory
  NOTE_TO_PC = {
    'C' => 0, 'C#' => 1, 'DB' => 1, 'D' => 2, 'D#' => 3, 'EB' => 3, 'E' => 4,
    'F' => 5, 'F#' => 6, 'GB' => 6, 'G' => 7, 'G#' => 8, 'AB' => 8, 'A' => 9,
    'A#' => 10, 'BB' => 10, 'B' => 11,
  }.freeze
  PC_NAMES_FLAT = %w[C Db D Eb E F Gb G Ab A Bb B].freeze
  MAJOR_SCALE_SEMITONES = [0, 2, 4, 5, 7, 9, 11].freeze

  CHORD_TONES = {
    maj: [0, 4, 7], min: [0, 3, 7], sus2: [0, 2, 7],
    maj7: [0, 4, 7, 11], maj9: [0, 4, 7, 11, 14], add9: [0, 4, 7, 14], six: [0, 4, 7, 9],
    m7: [0, 3, 7, 10], m9: [0, 3, 7, 10, 14], m11: [0, 3, 7, 10, 14, 17],
    dom7: [0, 4, 7, 10], dom7sus4: [0, 5, 7, 10], dom9: [0, 4, 7, 10, 14], sus9: [0, 5, 7, 10, 14],
    dom7sharp9: [0, 4, 7, 10, 15], m7b5: [0, 3, 6, 10], dim7: [0, 3, 6, 9],
    # Fully altered dominant: b7, b9, AND #9, no natural 9th or 5th — the
    # maximum-tension jazz "alt" chord (Coltrane-era), all extensions bent
    # toward dissonance instead of color.
    alt7: [0, 4, 10, 13, 15],
    # maj7 with the 11th sharped instead of natural — Lydian color,
    # used by the real "industrial_techno_dilla" progression below.
    maj7sharp11: [0, 4, 7, 11, 18],
  }.freeze
  CHORD_SUFFIX = {
    maj: '', min: 'm', sus2: 'sus2',
    maj7: 'maj7', maj9: 'maj9', add9: 'add9', six: '6', m7: 'm7', m9: 'm9', m11: 'm11',
    dom7: '7', dom7sus4: '7sus4', dom9: '9', sus9: 'sus9', dom7sharp9: '7#9', m7b5: 'm7b5', dim7: 'dim7',
    alt7: '7alt', maj7sharp11: 'maj7#11',
  }.freeze

  PROGRESSIONS = {
    ii_V_I: [[2, :m7], [5, :dom7], [1, :maj9]],
    vi_circle: [[1, :maj9], [6, :m9], [2, :m7], [5, :dom7sus4]],
    pop_jazz: [[1, :maj9], [6, :m7], [4, :maj7], [5, :dom7]],
    chromatic_drift: [[1, :maj9], ['b7', :maj7], [4, :maj7], [4, :m7]],
  }.freeze

  ABSOLUTE_PROGRESSIONS = {
    los_angeles: { bpm: 85, voicing: :spread, fx: :flylo_cosmic,
                   chords: [[10, :maj9], [9, :m9], [7, :dom7sus4], [5, :maj9]] },
    time_donut: { bpm: 90, voicing: :spread, fx: :dilla_butter, chords: [[1, :maj7], [0, :m7], [5, :m7], [10, :m7]] },
    how_does_it_feel: { bpm: 92, voicing: :spread, fx: :analog_lush,
                         chords: [[2, :add9], [9, :dom7sus4], [7, :six], [0, :dom9],
                                  [6, :m9], [11, :dom9], [4, :m9], [9, :sus9]] },
    voodoo_vamp: { bpm: 86, voicing: :quartal, fx: :warm_tape, chords: [[5, :m9], [10, :m9]] },
    backdoor_gospel: { bpm: 78, voicing: :quartal, fx: :analog_lush,
                       chords: [[0, :maj9], [5, :m9], [10, :dom9], [0, :maj9]] },
    # Dark/minor, real contrapuntal motion: chromatic descending "lament
    # bass" A-G-F#-F-E (Purcell/Bach's device for tragic affect) — every
    # chord is minor, half-diminished, or fully altered (no major-quality
    # chords) so brightness doesn't undercut the descent.
    lament_dark: { bpm: 80, voicing: :spread, fx: :vinyl_worn,
                   chords: [[9, :m9], [7, :m7], [6, :m7b5], [5, :m9], [4, :alt7]] },
    # Real, evidence-cited progressions recovered from a sibling project's
    # research data (pub3/multimedia/dilla/dilla_data.json) — actual
    # transcribed harmony, not hand-derived approximations.
    dilla_life: { bpm: 90, voicing: :spread, fx: :dilla_butter, chords: [[10, :m9], [0, :dom7], [5, :m9], [10, :m9]] },
    hiphop_dark_epic: { bpm: 90, voicing: :spread, fx: :vinyl_worn,
                         chords: [[2, :min], [2, :min], [10, :maj7], [0, :maj], [7, :m7], [9, :m7],
                                  [2, :m9], [5, :maj], [7, :m9], [9, :dom7], [2, :m11], [0, :sus2]] },
    industrial_techno_dilla: { bpm: 130, voicing: :spread, fx: :sp1200_authentic,
                                chords: [[9, :m9], [2, :m7b5], [4, :m7], [5, :maj7sharp11]] },
    erykah_badu_on_and_on: { bpm: 92, voicing: :spread, fx: :dilla_butter,
                              chords: [[11, :m7], [7, :maj7], [11, :m7], [7, :maj7]] },
  }.freeze

  def self.pitch_class(name)
    NOTE_TO_PC.fetch(name.upcase) { raise ArgumentError, "unknown note #{name}" }
  end

  def self.degree_semitones(degree)
    return MAJOR_SCALE_SEMITONES[(degree - 1) % 7] + 12 * ((degree - 1) / 7) if degree.is_a?(Integer)

    flat, deg = degree.match(/(b?)(\d)/).captures
    base = MAJOR_SCALE_SEMITONES[deg.to_i - 1]
    flat == 'b' ? base - 1 : base
  end

  def self.progression_chords(key_root_pc, name)
    return ABSOLUTE_PROGRESSIONS.fetch(name)[:chords] if ABSOLUTE_PROGRESSIONS.key?(name)

    PROGRESSIONS.fetch(name).map { |degree, quality| [(key_root_pc + degree_semitones(degree)) % 12, quality] }
  end

  def self.absolute?(name)
    ABSOLUTE_PROGRESSIONS.key?(name)
  end

  def self.suggested_bpm(name)
    ABSOLUTE_PROGRESSIONS[name]&.fetch(:bpm, nil)
  end

  def self.recommended_voicing(name)
    ABSOLUTE_PROGRESSIONS[name]&.fetch(:voicing, nil) || :spread
  end

  def self.recommended_fx(name)
    ABSOLUTE_PROGRESSIONS[name]&.fetch(:fx, nil) || :dilla_butter
  end

  def self.chord_name(root_pc, quality)
    "#{PC_NAMES_FLAT[root_pc]}#{CHORD_SUFFIX.fetch(quality)}"
  end

  def self.build_chord_notes(root_pc, quality, octave: 4)
    root_midi = (12 * (octave + 1)) + root_pc
    CHORD_TONES.fetch(quality).map { |iv| root_midi + iv }
  end

  # Spread voicing: root dropped an octave into the (separately rendered)
  # bass, 5th omitted, top tone pushed up an octave. The root is never part
  # of the upper structure, so "chord instruments must never voice the
  # root as the lowest note" (constraint spec #2) holds by construction.
  def self.spread_voicing(notes, omit_fifth: true)
    root = notes.first
    upper = notes[1..]
    if omit_fifth && upper.size > 2
      fifth = root + 7
      upper = upper.reject { |n| n == fifth }
    end
    upper = upper.dup
    upper[-1] += 12 if upper.any?
    [root - 12] + upper
  end

  def self.quartal_voicing(notes)
    chord_pcs = notes.map { |n| n % 12 }
    start = notes[[1, notes.length - 1].min]
    stack = [start]
    3.times do
      candidate = stack.last + 5
      candidate_pc = candidate % 12
      nearest_pc = chord_pcs.min_by { |pc| [(pc - candidate_pc) % 12, (candidate_pc - pc) % 12].min }
      delta = (nearest_pc - candidate_pc) % 12
      delta -= 12 if delta > 6
      stack << candidate + delta
    end
    [notes.first - 12] + stack
  end

  def self.voice_lead_bass_sequence(root_pcs, base_octave: 2)
    prev = nil
    root_pcs.map do |pc|
      base_midi = (12 * (base_octave + 1)) + pc
      candidates = [base_midi - 12, base_midi, base_midi + 12]
      chosen = prev ? candidates.min_by { |c| (c - prev).abs } : base_midi
      prev = chosen
      chosen
    end
  end

  def self.midi_to_freq(midi)
    440.0 * (2**((midi - 69) / 12.0))
  end

  # Bach/Dilla theory rules: common-tone lock (a shared pitch class between
  # adjacent chords is held at the exact same octave rather than
  # restruck) and parallel 5th/8ve avoidance. NOTE: this is a different
  # criterion than constraint spec #2's "70% of voices move by step" —
  # it is not measured/enforced against that exact threshold.
  def self.refine_voice_leading!(voicings)
    (1...voicings.size).each do |i|
      prev = voicings[i - 1]
      curr = voicings[i]

      shared_pc = curr.map { |n| n % 12 }.find { |pc| prev.any? { |p| p % 12 == pc } }
      if shared_pc
        curr_idx = curr.index { |n| n % 12 == shared_pc }
        prev_note = prev.find { |p| p % 12 == shared_pc }
        curr[curr_idx] += (((prev_note - curr[curr_idx]) / 12.0).round * 12)
      end

      outer_prev = (prev.last - prev.first) % 12
      outer_curr = (curr.last - curr.first) % 12
      curr[-1] -= 2 if [0, 7].include?(outer_prev) && outer_prev == outer_curr
    end
    voicings
  end
end

# ---------------------------------------------------------------------------
# Groove: per-role phrase-drift LFO + Gaussian jitter micro-timing, plus
# per-producer base offsets (hiphop mode only — techno mode uses a global
# tension curve instead, see TechnoArrangement). Implements constraint
# spec #1 (per-instrument offsets, Gaussian not uniform jitter, phrase
# drift) but the exact distribution shape (spec: 80% within ±3ms, 5%
# within ±10-15ms) was tuned by feel, not fitted numerically to that target.
# ---------------------------------------------------------------------------
module Groove
  PRODUCER_BASE_MS = {
    dilla: { kick: 8, snare: -12, hat: 3, ghost: -5 },
    flylo: { kick: 12, snare: -8, hat: 6, ghost: -3 },
    madlib: { kick: 5, snare: -18, hat: 2, ghost: -8 }
  }.freeze

  ROLE_LFO = {
    kick: { period_mult: 1.0, phase: 0.0 },
    snare: { period_mult: 0.78, phase: Math::PI * 0.6 },
    hat: { period_mult: 1.35, phase: Math::PI * 1.3 },
    ghost: { period_mult: 0.6, phase: Math::PI * 0.25 }
  }.freeze

  PHRASE_BEATS = 6.0 * 4
  DEPTH_MS = 5.0

  def self.gaussian
    u1 = [rand, 1e-9].max
    u2 = rand
    Math.sqrt(-2 * Math.log(u1)) * Math.cos(2 * Math::PI * u2)
  end

  def self.offset_samples(instrument, beat_position, producer: :dilla)
    lfo = ROLE_LFO.fetch(instrument)
    period = PHRASE_BEATS * lfo[:period_mult]
    drift = DEPTH_MS * Math.sin((2 * Math::PI * beat_position / period) + lfo[:phase])
    jitter = gaussian * (DEPTH_MS / 3.0)
    jitter *= 3.5 if rand < 0.05
    ms = PRODUCER_BASE_MS.fetch(producer).fetch(instrument, 0) + drift + jitter
    (ms / 1000.0 * SAMPLE_RATE).round
  end
end

# ===========================================================================
# HIPHOP MODE — real SoX synthesis + effects
# ===========================================================================

# ---------------------------------------------------------------------------
# SoxShell: run sox, read the result back as a plain Ruby float array via a
# minimal WAV reader/writer. Every voice below writes its final stage as
# 16-bit mono PCM at SAMPLE_RATE specifically so this reader can parse it.
# ---------------------------------------------------------------------------
module SoxShell
  def self.run(cmd)
    ok = system("sox #{cmd}", %i[out err] => File::NULL)
    raise "sox failed: #{cmd}" unless ok
  end

  def self.read_wav(path)
    data = File.binread(path)
    pos = 12
    samples = nil
    while pos < data.bytesize - 8
      chunk_id = data[pos, 4]
      chunk_size = data[pos + 4, 4].unpack1('V')
      chunk_start = pos + 8
      samples = data[chunk_start, chunk_size].unpack('s<*') if chunk_id == 'data'
      pos = chunk_start + chunk_size
      pos += 1 if chunk_size.odd?
    end
    (samples || []).map { |s| s / 32_768.0 }
  end

  def self.write_wav(path, samples, sample_rate = SAMPLE_RATE)
    data = samples.map { |s| [(s.clamp(-1.0, 1.0) * 32_767).to_i].pack('s<') }.join
    File.open(path, 'wb') do |f|
      f.write('RIFF')
      f.write([36 + data.bytesize].pack('V'))
      f.write('WAVE')
      f.write('fmt ')
      f.write([16, 1, 1, sample_rate, sample_rate * 2, 2, 16].pack('VvvVVvv'))
      f.write('data')
      f.write([data.bytesize].pack('V'))
      f.write(data)
    end
  end
end

# ---------------------------------------------------------------------------
# WildFX: unusual SoX processing applied probabilistically per note/hit.
# OFF BY DEFAULT — an earlier version had this on by default and a full
# render was rejected immediately after ("no this is horrible!"); disabling
# it was one of several changes made in that pass, so its contribution to
# that specific verdict was never isolated. Opt in with --wild.
# ---------------------------------------------------------------------------
module WildFX
  @enabled = false
  class << self
    attr_accessor :enabled
  end

  RECIPES = [
    -> { "flanger #{rand(2..8)} #{rand(1..4)} #{rand(15..40)} #{rand(30..60)} #{rand(1..3)} sine" },
    -> { "phaser 0.6 0.66 #{rand(2..6)} #{(0.4 + rand * 0.4).round(2)} #{rand(1..3)} -t" },
    -> { "echo 0.8 0.7 #{rand(40..140)} #{(0.3 + rand * 0.3).round(2)}" },
    -> { "contrast #{rand(40..80)}" }
  ].freeze

  def self.maybe_apply(dir, samples, chance: 0.5)
    return samples if !enabled || samples.empty? || rand > chance

    recipe = RECIPES.sample.call
    tmp_in = "#{dir}/wildfx_in_#{rand(1_000_000)}.wav"
    tmp_out = "#{dir}/wildfx_out_#{rand(1_000_000)}.wav"
    SoxShell.write_wav(tmp_in, samples)
    begin
      SoxShell.run("#{tmp_in} -b 16 -e signed-integer -c 1 -r #{SAMPLE_RATE} #{tmp_out} #{recipe}")
      SoxShell.read_wav(tmp_out)
    rescue RuntimeError
      samples
    end
  end
end

# ---------------------------------------------------------------------------
# SoxVoice: instrument bodies ported from a sibling project's proven
# lib/synthesis.rb (pub3/multimedia/dilla).
# ---------------------------------------------------------------------------
module SoxVoice
  def self.rhodes(dir, freq, gain, duration)
    sin1, sin2, sin3, raw, out = %w[sin1 sin2 sin3 raw out].map { |n| "#{dir}/#{n}.wav" }
    SoxShell.run("-n -r #{SAMPLE_RATE} #{sin1} synth #{duration} sine #{freq} fade h 0.01 #{duration} 0.5 gain #{gain}")
    SoxShell.run("-n -r #{SAMPLE_RATE} #{sin2} synth #{duration} sine #{freq * 2} fade h 0.01 #{duration} 0.5 gain #{gain - 8}")
    SoxShell.run("-n -r #{SAMPLE_RATE} #{sin3} synth #{duration} sine #{freq * 3} fade h 0.01 #{duration} 0.5 gain #{gain - 12}")
    SoxShell.run("-m #{sin1} #{sin2} #{sin3} #{raw}")
    SoxShell.run("#{raw} -b 16 -e signed-integer -c 1 -r #{SAMPLE_RATE} #{out} tremolo 5.5 30 chorus 0.6 0.9 45 0.4 0.2 2 -t")
    SoxShell.read_wav(out)
  end

  def self.oberheim(dir, freq, gain, duration)
    detune = freq * 1.0046
    saw1, saw2, raw, out = %w[saw1 saw2 raw out].map { |n| "#{dir}/#{n}.wav" }
    SoxShell.run("-n -r #{SAMPLE_RATE} #{saw1} synth #{duration} sawtooth #{freq} fade h 1.5 #{duration} 3.5 gain #{gain}")
    SoxShell.run("-n -r #{SAMPLE_RATE} #{saw2} synth #{duration} sawtooth #{detune} fade h 1.5 #{duration} 3.5 gain #{gain - 2}")
    SoxShell.run("-m #{saw1} #{saw2} #{raw}")
    SoxShell.run("#{raw} -b 16 -e signed-integer -c 1 -r #{SAMPLE_RATE} #{out} lowpass 1500 chorus 0.7 0.85 48 0.5 0.28 2 -s")
    SoxShell.read_wav(out)
  end

  def self.minimoog(dir, freq, gain, duration, lowpass_hz: 1200)
    detune = freq * 1.0029
    saw, sqr, raw, out = %w[saw sqr raw out].map { |n| "#{dir}/#{n}.wav" }
    SoxShell.run("-n -r #{SAMPLE_RATE} #{saw} synth #{duration} sawtooth #{freq} fade h 1 #{duration} 4 gain #{gain}")
    SoxShell.run("-n -r #{SAMPLE_RATE} #{sqr} synth #{duration} square #{detune} fade h 1 #{duration} 4 gain #{gain - 3}")
    SoxShell.run("-m #{saw} #{sqr} #{raw}")
    SoxShell.run("#{raw} -b 16 -e signed-integer -c 1 -r #{SAMPLE_RATE} #{out} lowpass #{lowpass_hz} overdrive 5 chorus 0.6 0.9 40 0.4 0.2 2 -s")
    SoxShell.read_wav(out)
  end

  def self.cs80(dir, freq, gain, duration)
    detune = freq * 1.0091
    saw1, saw2, raw, out = %w[saw1 saw2 raw out].map { |n| "#{dir}/#{n}.wav" }
    SoxShell.run("-n -r #{SAMPLE_RATE} #{saw1} synth #{duration} sawtooth #{freq} fade h 3 #{duration} 4 gain #{gain}")
    SoxShell.run("-n -r #{SAMPLE_RATE} #{saw2} synth #{duration} sawtooth #{detune} fade h 3 #{duration} 4 gain #{gain - 2}")
    SoxShell.run("-m #{saw1} #{saw2} #{raw}")
    SoxShell.run("#{raw} -b 16 -e signed-integer -c 1 -r #{SAMPLE_RATE} #{out} lowpass 600 chorus 0.7 0.9 50 0.4 0.25 2 -t")
    SoxShell.read_wav(out)
  end

  # ARP Solina-style string ensemble: 3-voice detuned saws, lowpassed and
  # chorused then lightly overdriven.
  def self.strings(dir, freq, gain, duration)
    detune1 = freq * 1.0012
    detune2 = freq * 1.0023
    saw1, saw2, saw3, raw, chorused, out = %w[saw1 saw2 saw3 raw chorused out].map { |n| "#{dir}/#{n}.wav" }
    SoxShell.run("-n -r #{SAMPLE_RATE} #{saw1} synth #{duration} sawtooth #{freq} fade h 0.5 #{duration} 2 gain #{gain}")
    SoxShell.run("-n -r #{SAMPLE_RATE} #{saw2} synth #{duration} sawtooth #{detune1} fade h 0.5 #{duration} 2 gain #{gain - 1}")
    SoxShell.run("-n -r #{SAMPLE_RATE} #{saw3} synth #{duration} sawtooth #{detune2} fade h 0.5 #{duration} 2 gain #{gain - 2}")
    SoxShell.run("-m #{saw1} #{saw2} #{saw3} #{raw}")
    SoxShell.run("#{raw} #{chorused} lowpass 3000 chorus 0.7 0.9 55 0.5 0.3 2 -t")
    SoxShell.run("#{chorused} -b 16 -e signed-integer -c 1 -r #{SAMPLE_RATE} #{out} overdrive 3")
    SoxShell.read_wav(out)
  end

  # Brian Eno-style ambient pad: sine + a subtly detuned saw.
  def self.ambient(dir, freq, gain, duration)
    detune = freq * 1.0006
    sine, saw, out = %w[sine saw out].map { |n| "#{dir}/#{n}.wav" }
    SoxShell.run("-n -r #{SAMPLE_RATE} #{sine} synth #{duration} sine #{freq} fade h 5 #{duration} 6 gain #{gain}")
    SoxShell.run("-n -r #{SAMPLE_RATE} #{saw} synth #{duration} sawtooth #{detune} fade h 5 #{duration} 6 gain #{gain - 8}")
    SoxShell.run("-m #{sine} #{saw} -b 16 -e signed-integer -c 1 -r #{SAMPLE_RATE} #{out} highpass 80")
    SoxShell.read_wav(out)
  end

  # Root sine + sub-bass an octave down. NOTE: constraint spec #2 asks for
  # bass strictly bandlimited to 30-120Hz; this is NOT currently enforced
  # here (no highpass/lowpass on the bass voice) — a reviewer wanting to
  # apply that constraint should add one.
  def self.sub_bass(dir, freq, gain, duration)
    root, sub, out = %w[root sub out].map { |n| "#{dir}/#{n}.wav" }
    SoxShell.run("-n -r #{SAMPLE_RATE} #{root} synth #{duration} sine #{freq} fade h 0.02 #{duration} 0.3 gain #{gain}")
    SoxShell.run("-n -r #{SAMPLE_RATE} #{sub} synth #{duration} sine #{freq / 2} fade h 0.02 #{duration} 0.3 gain #{gain - 3}")
    SoxShell.run("-m #{root} #{sub} -b 16 -e signed-integer -c 1 -r #{SAMPLE_RATE} #{out}")
    SoxShell.read_wav(out)
  end
end

# ---------------------------------------------------------------------------
# SoxDrums: kick/snare/hat recipes ported from the same sibling project's
# drums_consolidated.rb (an SP-1200-style kit). Overdrive/gain were cut
# from the original pub3 values (10/8 -> 4/3, hats -12/-10 -> -18/-16)
# after a spectrogram showed every drum hit blasting full-spectrum energy
# to 22kHz at near-0dB; this reduced but did not eliminate the effect (see
# STATUS header — some of that full-spectrum energy turned out to be
# expected broadband content from noise-based percussion, not a bug).
# ---------------------------------------------------------------------------
module SoxDrums
  def self.kick(dir)
    out = "#{dir}/kick_#{rand(1_000_000)}.wav"
    SoxShell.run("-n -r #{SAMPLE_RATE} -b 16 -e signed-integer -c 1 #{out} synth 0.16 sine 58 fade h 0.001 0.16 0.06 overdrive 4 gain -6")
    SoxShell.read_wav(out)
  end

  def self.snare(dir)
    out = "#{dir}/snare_#{rand(1_000_000)}.wav"
    SoxShell.run("-n -r #{SAMPLE_RATE} -b 16 -e signed-integer -c 1 #{out} synth 0.12 noise lowpass 4000 highpass 200 fade h 0.001 0.12 0.04 overdrive 3 gain -9")
    SoxShell.read_wav(out)
  end

  def self.hat(dir, open: false)
    out = "#{dir}/hat_#{rand(1_000_000)}.wav"
    if open
      SoxShell.run("-n -r #{SAMPLE_RATE} -b 16 -e signed-integer -c 1 #{out} synth 0.25 noise highpass 6000 fade h 0.001 0.25 0.15 gain -16")
    else
      SoxShell.run("-n -r #{SAMPLE_RATE} -b 16 -e signed-integer -c 1 #{out} synth 0.06 noise highpass 7000 fade h 0.001 0.06 0.02 gain -18")
    end
    SoxShell.read_wav(out)
  end
end

# ---------------------------------------------------------------------------
# SoxMaster: mastering chains adapted from pub3/multimedia/dilla/
# dilla_data.json "vintage_fx_chains" — real, cited SoX chains, not
# invented parameters. The original compand curves used an UPWARD
# EXPANSION segment (e.g. "-inf,-70,-55,-20") correct for real recordings
# with tape/room noise in that range, but CONFIRMED VIA SPECTROGRAM to
# instead amplify this engine's digital quantization floor into audible
# broadband hiss. Replaced with downward-only compressor curves that keep
# each chain's character but don't manufacture noise from silence.
# ---------------------------------------------------------------------------
module SoxMaster
  CHAINS = {
    dilla_butter: 'compand 0.1,0.3 -60,-60,-30,-15,-10,-6 -3 reverb 20 50 70 norm -2',
    warm_tape: 'compand 0.3,1 -60,-60,-30,-18,-10,-8 -3 reverb 25 50 65 norm -2',
    lofi_dream: 'compand 0.05,0.2 -55,-55,-25,-12,-10,-6 -4 reverb 28 60 75 norm -2',
    analog_lush: 'compand 0.2,0.4 -60,-60,-35,-18,-15,-10 -3 reverb 32 60 80 norm -2',
    vinyl_worn: 'highpass 60 lowpass 10000 compand 0.1,0.2 -55,-55,-25,-12,-10,-6 -4 tremolo 0.3 0.15 gain -3 norm -2',
    sp1200_authentic: 'rate 26040 compand 0.02,0.05 -50,-50,-20,-10,-8,-6 -3 ' \
                       'overdrive 10 treble -3 1200 0.5s gain -6 rate 44100',
    flylo_cosmic: 'compand 0.05,0.15 -55,-55,-20,-8,-6,-4 -5 ' \
                  'chorus 0.7 0.9 55 0.4 0.25 2 -t chorus 0.6 0.8 40 0.5 0.3 2 -s ' \
                  'reverb 35 70 75 phaser 0.8 0.7 3 0.6 0.5 -t norm -2',
    jneiro_texture: 'compand 0.12,0.25 -55,-55,-25,-10,-8,-6 -4 overdrive 8 ' \
                     'flanger 0.6 0.87 3.0 0.9 0.5 tremolo 4.5 70 reverb 25 55 65 norm -2',
    off: 'gain -n -1'
  }.freeze

  CRACKLE = {
    vinyl_worn: 'synth brownnoise gain -35 highpass 2000 lowpass 8000'
  }.freeze

  def self.process(input_path, output_path, chain_name)
    return SoxShell.run("#{input_path} -b 16 -e signed-integer -c 1 -r #{SAMPLE_RATE} #{output_path} #{CHAINS.fetch(:off)}") if chain_name == :off

    fx_path = "#{File.dirname(output_path)}/fx_stage.wav"
    SoxShell.run("#{input_path} #{fx_path} #{CHAINS.fetch(chain_name)}")

    crackle_recipe = CRACKLE[chain_name]
    unless crackle_recipe
      SoxShell.run("#{fx_path} -b 16 -e signed-integer -c 1 -r #{SAMPLE_RATE} #{output_path} gain -n -1")
      return
    end

    duration = `sox --info -D #{fx_path}`.strip.to_f
    crackle_path = "#{File.dirname(output_path)}/crackle.wav"
    SoxShell.run("-n -r #{SAMPLE_RATE} #{crackle_path} #{crackle_recipe} trim 0 #{duration}")
    SoxShell.run("-m #{fx_path} #{crackle_path} -b 16 -e signed-integer -c 1 -r #{SAMPLE_RATE} #{output_path} gain -n -1")
  end
end

# ---------------------------------------------------------------------------
# HiphopArrangement: proportional 4-section form.
# ---------------------------------------------------------------------------
module HiphopArrangement
  SECTION_FRACTIONS = [[:intro, 0.2], [:groove, 0.45], [:breakdown, 0.15], [:return, 0.2]].freeze
  SECTION_LAYERS = {
    intro: { harmony: %i[rhodes], bass: false, drums: false },
    groove: { harmony: %i[rhodes pad], bass: true, drums: :full },
    breakdown: { harmony: %i[swell pad], bass: true, drums: :sparse },
    return: { harmony: %i[rhodes pad swell], bass: true, drums: :full }
  }.freeze
  INSTRUMENT_GAIN = { rhodes: 0.9, pad: 0.5, swell: 0.6 }.freeze

  def self.section_for_each_bar(total_bars)
    counts = SECTION_FRACTIONS.map { |name, frac| [name, (total_bars * frac).round] }
    diff = total_bars - counts.sum { |_, c| c }
    counts[1][1] += diff
    counts.flat_map { |name, count| Array.new([count, 0].max, name) }
  end
end

# ---------------------------------------------------------------------------
# HiphopTrackBuilder: wires Theory + SoX voices/drums + arrangement into
# one rendered buffer. Every note/hit is synthesized by SoX into a scratch
# dir, read back as a float array, and mixed at the exact Groove-computed
# sample offset — SoX does the sound, Ruby does the timing.
# ---------------------------------------------------------------------------
module HiphopTrackBuilder
  def self.mix_into(buffer, sound, start_sample, gain = 1.0)
    sound.each_with_index do |s, i|
      idx = start_sample + i
      next if idx.negative? || idx >= buffer.size

      buffer[idx] += s * gain
    end
  end

  def self.render(bpm:, bars:, progression:, key:, producer: :dilla, voicing: nil, master: nil, pad_voice: :strings)
    Dir.mktmpdir('hiphop_sox') do |dir|
      key_pc = Theory.absolute?(progression) ? nil : Theory.pitch_class(key)
      base_chords = Theory.progression_chords(key_pc, progression)
      chord_names = base_chords.map { |pc, q| Theory.chord_name(pc, q) }
      voicing ||= Theory.recommended_voicing(progression)
      master ||= Theory.recommended_fx(progression)

      sections = HiphopArrangement.section_for_each_bar(bars)
      flattened = Array.new(bars) { |i| base_chords[i % base_chords.length] }
      upper_voicings = flattened.map do |pc, q|
        base_notes = Theory.build_chord_notes(pc, q, octave: 4)
        voicing == :quartal ? Theory.quartal_voicing(base_notes) : Theory.spread_voicing(base_notes)
      end
      Theory.refine_voice_leading!(upper_voicings)
      bass_notes = Theory.voice_lead_bass_sequence(flattened.map(&:first), base_octave: 2)

      samples_per_beat = SAMPLE_RATE * 60.0 / bpm
      samples_per_step = samples_per_beat / 4.0
      samples_per_bar = samples_per_step * STEPS_PER_BAR
      total_samples = (bars * samples_per_bar).ceil + SAMPLE_RATE

      buffer = Array.new(total_samples, 0.0)

      bars.times do |bar_i|
        section = sections[bar_i]
        layers = HiphopArrangement::SECTION_LAYERS.fetch(section)
        bar_start = (bar_i * samples_per_bar).round
        bar_duration_s = samples_per_bar / SAMPLE_RATE.to_f

        notes = upper_voicings[bar_i]
        gain_per_note = -6 - (Math.log2(notes.size) * 3)
        layers[:harmony].each do |instr|
          notes.each do |midi|
            freq = Theory.midi_to_freq(midi)
            snd = case instr
                  when :rhodes then SoxVoice.rhodes(dir, freq, gain_per_note, bar_duration_s)
                  when :pad then SoxVoice.public_send(pad_voice, dir, freq, gain_per_note, bar_duration_s)
                  when :swell then SoxVoice.cs80(dir, freq, gain_per_note, bar_duration_s * 1.2)
                  end
            snd = WildFX.maybe_apply(dir, snd, chance: 0.5)
            mix_into(buffer, snd, bar_start, HiphopArrangement::INSTRUMENT_GAIN.fetch(instr))
          end
        end

        if layers[:bass]
          freq = Theory.midi_to_freq(bass_notes[bar_i])
          [0, 10].each do |step|
            snd = SoxVoice.sub_bass(dir, freq, -4, samples_per_step * 3 / SAMPLE_RATE)
            snd = WildFX.maybe_apply(dir, snd, chance: 0.25)
            mix_into(buffer, snd, bar_start + (step * samples_per_step).round, 0.8)
          end
        end

        drums_mode = layers[:drums]
        next unless drums_mode

        STEPS_PER_BAR.times do |step|
          step_sample = bar_start + (step * samples_per_step).round
          beat_position = ((bar_i * STEPS_PER_BAR) + step) / 4.0

          if drums_mode == :full
            if [0, 6, 10].include?(step)
              t = step_sample + Groove.offset_samples(:kick, beat_position, producer: producer)
              kick_snd = WildFX.maybe_apply(dir, SoxDrums.kick(dir), chance: 0.15)
              mix_into(buffer, kick_snd, t, 1.0)
            end
            if [4, 12].include?(step)
              t = step_sample + Groove.offset_samples(:snare, beat_position, producer: producer)
              snare_snd = WildFX.maybe_apply(dir, SoxDrums.snare(dir), chance: 0.35)
              mix_into(buffer, snare_snd, t, 0.9)
              if rand < 0.15
                rand(2..3).times do |r|
                  mix_into(buffer, SoxDrums.snare(dir), t + ((r + 1) * 900), 0.9 * (0.6**(r + 1)))
                end
              end
            end
            if [7, 15].include?(step)
              t = step_sample + Groove.offset_samples(:ghost, beat_position, producer: producer)
              mix_into(buffer, SoxDrums.snare(dir), t, 0.3)
            end
          end

          if [2, 6, 10, 14].include?(step)
            t = step_sample + Groove.offset_samples(:hat, beat_position, producer: producer)
            hat_snd = WildFX.maybe_apply(dir, SoxDrums.hat(dir), chance: 0.3)
            mix_into(buffer, hat_snd, t, 0.22)
            if rand < 0.1
              rand(3..4).times do |r|
                mix_into(buffer, SoxDrums.hat(dir), t + ((r + 1) * 700), 0.15 + (r * 0.04))
              end
            end
          end
          if step == 14
            t = step_sample + Groove.offset_samples(:hat, beat_position, producer: producer)
            open_hat_snd = WildFX.maybe_apply(dir, SoxDrums.hat(dir, open: true), chance: 0.4)
            mix_into(buffer, open_hat_snd, t, 0.25)
          end
        end
      end

      peak = buffer.map(&:abs).max
      buffer.map! { |s| s / peak * 0.9 } if peak&.positive?

      raw_path = File.join(dir, 'raw_mix.wav')
      SoxShell.write_wav(raw_path, buffer)
      mastered_path = File.join(dir, 'mastered.wav')
      SoxMaster.process(raw_path, mastered_path, master)
      mastered = SoxShell.read_wav(mastered_path)

      [mastered, { chord_names: chord_names, sections: sections }]
    end
  end
end

# ===========================================================================
# TECHNO MODE — hand-rolled Ruby DSP (NOT migrated to SoX; see STATUS header)
# ===========================================================================

# ---------------------------------------------------------------------------
# Modes: the harmonic void. No cadences, no resolution — a mode to
# snap a hypnotic cell into.
# ---------------------------------------------------------------------------
module Modes
  PHRYGIAN = [0, 1, 3, 5, 7, 8, 10].freeze
  LOCRIAN = [0, 1, 3, 5, 6, 8, 10].freeze

  def self.snap(relative_semitone, scale)
    rel = relative_semitone % 12
    octave_shift = (relative_semitone - rel) / 12 * 12
    nearest = scale.min_by { |s| (s - rel).abs }
    nearest + octave_shift
  end
end

# ---------------------------------------------------------------------------
# HypnoticSequence: a 3-6 note loop built from the 0/+3/+6 semitone cell
# common to Birmingham/Spanish techno, folded into the chosen mode.
# ---------------------------------------------------------------------------
module HypnoticSequence
  def self.build(root_pc:, scale:, length:, octave: 2)
    cell = [0, 3, 6, 3, 0, -2]
    root_midi = (12 * (octave + 1)) + root_pc
    Array.new(length) do |i|
      offset = Modes.snap(cell[i % cell.length], scale)
      root_midi + offset
    end
  end
end

# ---------------------------------------------------------------------------
# Filter: minimal one-pole high/lowpass.
# ---------------------------------------------------------------------------
module Filter
  def self.highpass(buffer, cutoff_hz)
    rc = 1.0 / (2 * Math::PI * cutoff_hz)
    dt = 1.0 / SAMPLE_RATE
    alpha = rc / (rc + dt)
    prev_in = 0.0
    prev_out = 0.0
    buffer.map do |s|
      out = alpha * (prev_out + s - prev_in)
      prev_in = s
      prev_out = out
      out
    end
  end

  def self.lowpass(buffer, cutoff_hz)
    alpha = (2 * Math::PI * cutoff_hz) / (SAMPLE_RATE + (2 * Math::PI * cutoff_hz))
    prev = 0.0
    buffer.map do |s|
      prev += (s - prev) * alpha
      prev
    end
  end
end

# ---------------------------------------------------------------------------
# Techno::Synth: the kick is everything here, so it gets three independent
# layers. The hypnotic sequence voice runs through a resonant-feeling
# one-pole lowpass whose cutoff is driven externally.
# ---------------------------------------------------------------------------
module Synth
  def self.env(n, attack:, decay:)
    a = (attack * n).to_i.clamp(1, n)
    Array.new(n) do |i|
      if i < a
        i / a.to_f
      else
        d = (i - a) / [n - a, 1].max.to_f
        Math.exp(-decay * d)
      end
    end
  end

  def self.soft_clip(x, drive)
    Math.tanh(x * drive) / Math.tanh(drive)
  end

  # PolyBLEP: band-limits the sawtooth's phase discontinuity so it doesn't
  # alias into inharmonic garbage above Nyquist.
  def self.poly_blep(t, dt)
    if t < dt
      t /= dt
      return t + t - (t * t) - 1.0
    elsif t > 1.0 - dt
      t = (t - 1.0) / dt
      return (t * t) + t + t + 1.0
    end
    0.0
  end

  def self.band_limited_saw(phase, dt)
    ((2.0 * phase) - 1.0) - poly_blep(phase, dt)
  end

  def self.techno_kick(duration_s: 0.8, sub_freq: 50.0)
    n = (duration_s * SAMPLE_RATE).to_i
    click_n = (0.006 * SAMPLE_RATE).to_i
    phase = 0.0
    Array.new(n) do |i|
      t = i / SAMPLE_RATE.to_f
      freq = sub_freq + (60.0 * Math.exp(-t * 40))
      phase += freq / SAMPLE_RATE
      sub = Math.sin(2 * Math::PI * phase) * Math.exp(-t * 3.5)
      click = i < click_n ? ((rand * 2) - 1) * Math.exp(-t * 500) * 0.5 : 0.0
      top_freq = 180.0 * Math.exp(-t * 30) + 40.0
      top = Math.sin(2 * Math::PI * top_freq * t) * Math.exp(-t * 18) * 0.3
      sub + click + top
    end
  end

  def self.rumble(duration_s: 2.0)
    n = (duration_s * SAMPLE_RATE).to_i
    amp = env(n, attack: 0.05, decay: 1.2)
    lp = 0.0
    Array.new(n) do |i|
      noise = (rand * 2) - 1
      lp += (noise - lp) * 0.05
      lp * amp[i] * 0.6
    end
  end

  def self.sequence_voice(freq, duration_s, cutoff_hz:, drive: 1.6)
    n = (duration_s * SAMPLE_RATE).to_i
    return [] if n <= 0

    phases = [0.0, 0.0]
    ratios = [1.0, 1.008]
    amp = env(n, attack: 0.002, decay: 5.5)
    alpha = (2 * Math::PI * cutoff_hz / SAMPLE_RATE).clamp(0.0, 1.0)
    lp_state = 0.0
    Array.new(n) do |i|
      s = 0.0
      2.times do |v|
        dt = (freq * ratios[v]) / SAMPLE_RATE
        phases[v] += dt
        phases[v] -= 1.0 if phases[v] >= 1.0
        s += band_limited_saw(phases[v], dt) * 0.5
      end
      lp_state += (s - lp_state) * alpha
      soft_clip(lp_state, drive) * amp[i]
    end
  end

  def self.metallic_hit(duration_s: 0.15)
    n = (duration_s * SAMPLE_RATE).to_i
    amp = env(n, attack: 0.0005, decay: 18.0)
    mod_phase = 0.0
    Array.new(n) do |i|
      t = i / SAMPLE_RATE.to_f
      noise = (rand * 2) - 1
      mod_phase += (1200 + (400 * Math.sin(2 * Math::PI * 3 * t))) / SAMPLE_RATE
      ring = Math.sin(2 * Math::PI * mod_phase)
      ((noise * 0.6) + (ring * 0.4)) * amp[i]
    end
  end

  def self.hihat(duration_s, open: false)
    n = (duration_s * SAMPLE_RATE).to_i
    amp = env(n, attack: 0.0005, decay: open ? 4.0 : 20.0)
    hp_prev = 0.0
    Array.new(n) do |i|
      noise = (rand * 2) - 1
      hp = noise - hp_prev
      hp_prev = noise
      hp * amp[i] * 0.5
    end
  end
end

# 2x oversample around a nonlinear stage, then lowpass + decimate. A
# waveshaper generates new harmonics exactly like an oscillator does, and
# those alias just as badly if applied straight at the working rate.
module Oversample
  def self.process(buffer, factor: 2)
    n = buffer.size
    up = Array.new(n * factor)
    n.times do |i|
      up[i * factor] = buffer[i]
      nxt = buffer[i + 1] || buffer[i]
      (factor - 1).times { |k| up[(i * factor) + 1 + k] = buffer[i] + ((nxt - buffer[i]) * (k + 1) / factor.to_f) }
    end
    processed = yield(up)
    filtered = Filter.lowpass(processed, SAMPLE_RATE / 2.2)
    Array.new(n) { |i| filtered[i * factor] }
  end
end

module Distortion
  # ONE oversampled clip stage with pre/post EQ, not N identical repeats:
  # chaining the same tanh in series repeatedly hardens the knee and
  # multiplies odd-harmonic order each pass — that reads as fizz, not warmth.
  def self.chain(buffer, stages: 2, drive: 1.25)
    out = Filter.highpass(buffer, 25.0)
    out = Oversample.process(out) { |up| up.map { |s| Synth.soft_clip(s, drive) } }
    out = Filter.lowpass(out, 9000.0 - ((stages - 1) * 1200))
    out
  end
end

# ---------------------------------------------------------------------------
# Texture: a Freeverb-style reverb sized for warehouse decay, and a HARD
# sidechain duck.
# ---------------------------------------------------------------------------
module Texture
  def self.reverb(buffer, mix: 0.3, room_size: 0.6, damp: 0.25)
    comb_delays = [1116, 1188, 1277, 1356, 1422, 1491, 1557, 1617]
    allpass_delays = [556, 441, 341, 225]
    feedback = (room_size * 0.28) + 0.7
    allpass_feedback = 0.5
    n = buffer.size
    wet = Array.new(n, 0.0)

    comb_delays.each do |d|
      line = Array.new(d, 0.0)
      idx = 0
      filter_store = 0.0
      n.times do |i|
        delayed = line[idx]
        filter_store = (delayed * (1 - damp)) + (filter_store * damp)
        wet[i] += delayed
        line[idx] = buffer[i] + (filter_store * feedback)
        idx += 1
        idx = 0 if idx == d
      end
    end
    wet.map! { |s| s / comb_delays.size }

    allpass_delays.each do |d|
      line = Array.new(d, 0.0)
      idx = 0
      n.times do |i|
        delayed = line[idx]
        input = wet[i]
        out = (-input * allpass_feedback) + delayed
        line[idx] = input + (delayed * allpass_feedback)
        idx += 1
        idx = 0 if idx == d
        wet[i] = out
      end
    end

    Array.new(n) { |i| (buffer[i] * (1 - mix)) + (wet[i] * mix) }
  end

  # Implements constraint spec #3's kick/bass sidechain rule, but only for
  # techno mode and only kick-vs-(seq/rumble) — there is no general
  # spectral-slot ducking (e.g. snare-triggered harmony ducking) anywhere.
  def self.sidechain_duck!(buffer, onsets, depth: 0.85, release_ms: 220)
    release_samples = (release_ms / 1000.0 * SAMPLE_RATE).to_i
    onsets.each do |onset|
      release_samples.times do |i|
        idx = onset + i
        next if idx.negative? || idx >= buffer.size

        env = 1.0 - (depth * (1.0 - (i / release_samples.to_f)))
        buffer[idx] *= env
      end
    end
  end

  def self.echo(buffer, delay_ms: 180, feedback: 0.4, mix: 0.35)
    n = buffer.size
    d = [(delay_ms / 1000.0 * SAMPLE_RATE).to_i, 1].max
    line = Array.new(d, 0.0)
    idx = 0
    wet = Array.new(n)
    n.times do |i|
      delayed = line[idx]
      wet[i] = delayed
      line[idx] = buffer[i] + (delayed * feedback)
      idx += 1
      idx = 0 if idx == d
    end
    Array.new(n) { |i| (buffer[i] * (1 - mix)) + (wet[i] * mix) }
  end

  def self.bitcrush(buffer, bits: 8, downsample: 3)
    prefiltered = Filter.lowpass(buffer, SAMPLE_RATE / (2.0 * downsample))
    levels = 2**bits
    held = 0.0
    prefiltered.each_with_index.map do |s, i|
      held = s if (i % downsample).zero?
      (held * levels).round / levels.to_f
    end
  end
end

# ---------------------------------------------------------------------------
# TechnoMaster: harder knee, lower threshold than the jazz-hop chain.
# ---------------------------------------------------------------------------
module TechnoMaster
  def self.soft_knee_compress(buffer, threshold: 0.45, ratio: 4.0, attack: 0.003, release: 0.1)
    attack_coef = Math.exp(-1.0 / (attack * SAMPLE_RATE))
    release_coef = Math.exp(-1.0 / (release * SAMPLE_RATE))
    envelope = 0.0
    buffer.map do |input|
      rectified = input.abs
      coef = rectified > envelope ? attack_coef : release_coef
      envelope = (coef * envelope) + ((1 - coef) * rectified)
      gain = 1.0
      if envelope > threshold
        excess = envelope - threshold
        compressed = threshold + (excess / ratio)
        gain = compressed / envelope
      end
      input * gain
    end
  end

  def self.normalize(buffer, target_dbfs: -0.5)
    peak = buffer.map(&:abs).max
    return buffer if peak.nil? || peak.zero?

    scale = (10**(target_dbfs / 20.0)) / peak
    buffer.map { |s| s * scale }
  end
end

# ---------------------------------------------------------------------------
# Sonitex: pure-Ruby emulation of the Sonitex STX-1260 lo-fi chain (a
# specific VST plugin by Tone Projects) — NOT the MPC-3000/SDE-3000
# hardware named in constraint spec #7. "heavy" is the default.
# ---------------------------------------------------------------------------
module Sonitex
  DONUTS_SOUL = {
    dist_drive: 1.12, dist_mix: 0.32, dist_dc: 0.025, warmth_db: 3.0,
    hf_rolloff: 14_200, lf_rolloff: 30, head_bump_hz: 58, head_bump_db: 2.2,
    crush_bits: 13, crush_sr: 1.4, crush_mix: 0.14, crush_post_lp: 8_500,
    hiss_amp: 0.0005, pop_rate: 0.0002, pop_amp: 0.10, click_rate: 0.0001,
    out_comp_threshold: -21, out_comp_ratio: 2.0, out_comp_makeup: 1.2,
    limit: 0.95, level_out: 0.97
  }.freeze

  HEAVY = {
    dist_drive: 3.6, dist_mix: 0.88, dist_dc: 0.09, warmth_db: 7.0,
    hf_rolloff: 9_600, lf_rolloff: 45, head_bump_hz: 58, head_bump_db: 6.0,
    crush_bits: 8, crush_sr: 2.05, crush_mix: 0.58, crush_post_lp: 2_400,
    hiss_amp: 0.006, pop_rate: 0.0009, pop_amp: 0.24, click_rate: 0.0012,
    out_comp_threshold: -15, out_comp_ratio: 4.0, out_comp_makeup: 3.0,
    limit: 0.84, level_out: 0.86
  }.freeze

  PRESETS = { donuts_soul: DONUTS_SOUL, heavy: HEAVY }.freeze

  def self.pre_emphasis(buffer, boost_db, freq_hz: 3000.0)
    return buffer if boost_db.zero?

    hp = Filter.highpass(buffer, freq_hz)
    gain = (10**(boost_db / 20.0)) - 1.0
    buffer.each_index.map { |i| buffer[i] + (hp[i] * gain) }
  end

  # True peaking EQ, RBJ Audio EQ Cookbook formula.
  def self.head_bump(buffer, freq_hz, boost_db)
    return buffer if boost_db.zero?

    a = 10**(boost_db / 40.0)
    q = 1.0
    w0 = 2 * Math::PI * freq_hz / SAMPLE_RATE
    alpha = Math.sin(w0) / (2 * q)
    cos_w0 = Math.cos(w0)
    b0 = 1 + (alpha * a)
    b1 = -2 * cos_w0
    b2 = 1 - (alpha * a)
    a0 = 1 + (alpha / a)
    a1 = -2 * cos_w0
    a2 = 1 - (alpha / a)
    x1 = x2 = y1 = y2 = 0.0
    buffer.map do |x0|
      y0 = ((b0 / a0) * x0) + ((b1 / a0) * x1) + ((b2 / a0) * x2) - ((a1 / a0) * y1) - ((a2 / a0) * y2)
      x2 = x1
      x1 = x0
      y2 = y1
      y1 = y0
      y0
    end
  end

  def self.tape_distortion(buffer, drive:, mix:, dc:)
    wet = Oversample.process(buffer) do |up|
      norm = Math.tanh(drive)
      up.map { |s| Math.tanh((s + dc) * drive) / norm }
    end
    buffer.each_index.map { |i| (buffer[i] * (1 - mix)) + (wet[i] * mix) }
  end

  def self.bit_crush(buffer, bits:, sr_ratio:, mix:, post_lp:)
    step = [sr_ratio.round, 1].max
    prefiltered = Filter.lowpass(buffer, SAMPLE_RATE / (2.0 * step))
    levels = 2**bits
    held = 0.0
    crushed = prefiltered.each_with_index.map do |s, i|
      held = s if (i % step).zero?
      (held * levels).round / levels.to_f
    end
    crushed = Filter.lowpass(crushed, post_lp)
    buffer.each_index.map { |i| (buffer[i] * (1 - mix)) + (crushed[i] * mix) }
  end

  def self.hiss_and_pop(buffer, hiss_amp:, pop_rate:, pop_amp:, click_rate:)
    buffer.map do |s|
      s += ((rand * 2) - 1) * hiss_amp
      s += ((rand * 2) - 1) * pop_amp if rand < pop_rate
      s += ((rand * 2) - 1) * pop_amp * 0.5 if rand < click_rate
      s
    end
  end

  def self.output_compress(buffer, threshold_db:, ratio:, makeup_db:)
    threshold = 10**(threshold_db / 20.0)
    makeup = 10**(makeup_db / 20.0)
    attack_coef = Math.exp(-1.0 / (0.005 * SAMPLE_RATE))
    release_coef = Math.exp(-1.0 / (0.12 * SAMPLE_RATE))
    envelope = 0.0
    buffer.map do |input|
      rectified = input.abs
      coef = rectified > envelope ? attack_coef : release_coef
      envelope = (coef * envelope) + ((1 - coef) * rectified)
      gain = 1.0
      if envelope > threshold
        excess = envelope - threshold
        compressed = threshold + (excess / ratio)
        gain = compressed / envelope
      end
      input * gain * makeup
    end
  end

  def self.process(buffer, preset_name)
    return buffer if preset_name == :off

    preset = PRESETS.fetch(preset_name)
    out = pre_emphasis(buffer, preset[:warmth_db])
    out = tape_distortion(out, drive: preset[:dist_drive], mix: preset[:dist_mix], dc: preset[:dist_dc])
    out = head_bump(out, preset[:head_bump_hz], preset[:head_bump_db])
    out = Filter.highpass(out, preset[:lf_rolloff])
    out = Filter.lowpass(out, preset[:hf_rolloff])
    out = bit_crush(out, bits: preset[:crush_bits], sr_ratio: preset[:crush_sr], mix: preset[:crush_mix],
                          post_lp: preset[:crush_post_lp])
    out = hiss_and_pop(out, hiss_amp: preset[:hiss_amp], pop_rate: preset[:pop_rate], pop_amp: preset[:pop_amp],
                             click_rate: preset[:click_rate])
    out = output_compress(out, threshold_db: preset[:out_comp_threshold], ratio: preset[:out_comp_ratio],
                                makeup_db: preset[:out_comp_makeup])
    out.map { |s| s.clamp(-preset[:limit], preset[:limit]) * preset[:level_out] }
  end
end

# ---------------------------------------------------------------------------
# NastyVCS: mono "Summing Phasy" console-glue chain. Stereo width/Haas
# jitter need two channels; this engine is mono, so those are left out
# rather than faked.
# ---------------------------------------------------------------------------
module NastyVCS
  def self.parallel_compress(buffer, blend: 0.4)
    compressed = Sonitex.output_compress(buffer, threshold_db: -28, ratio: 9.0, makeup_db: 7.0)
    buffer.each_index.map { |i| (buffer[i] * (1 - blend)) + (compressed[i] * blend) }
  end

  def self.harmonic_bloom(buffer, amount: 0.2)
    Oversample.process(buffer) { |up| up.map { |s| s + (amount * s.abs * s) } }
  end

  def self.tilt_eq(buffer, low_gain_db: 2.0, high_gain_db: 1.5, low_hz: 100.0, high_hz: 7000.0)
    low = Filter.lowpass(buffer, low_hz)
    high = Filter.highpass(buffer, high_hz)
    low_gain = (10**(low_gain_db / 20.0)) - 1.0
    high_gain = (10**(high_gain_db / 20.0)) - 1.0
    buffer.each_index.map { |i| buffer[i] + (low[i] * low_gain) + (high[i] * high_gain) }
  end

  def self.summing_glue(buffer)
    parallel_compress(buffer)
      .then { |compressed| harmonic_bloom(compressed) }
      .then { |bloomed| tilt_eq(bloomed) }
  end
end

# ---------------------------------------------------------------------------
# TechnoArrangement: pressure, not drops. A linear tension curve (0..1
# across the whole track) opens the sequence filter and deepens distortion
# instead of a build/breakdown/drop template. NOTE: no per-instrument
# Groove-style micro-timing exists in techno mode (see STATUS header).
# ---------------------------------------------------------------------------
module TechnoArrangement
  def self.schedule(total_bars)
    {
      kick_start: [4, (total_bars * 0.08).round].max,
      percussion_start: (total_bars * 0.35).round,
      second_voice_start: (total_bars * 0.6).round,
      rumble_swell_start: (total_bars * 0.82).round
    }
  end

  def self.tension(bar_i, total_bars)
    (bar_i.to_f / total_bars).clamp(0.0, 1.0)
  end
end

# ---------------------------------------------------------------------------
# TechnoTrackBuilder
# ---------------------------------------------------------------------------
module TechnoTrackBuilder
  def self.mix_into(buffer, sound, start_sample, gain = 1.0)
    sound.each_with_index do |s, i|
      idx = start_sample + i
      next if idx.negative? || idx >= buffer.size

      buffer[idx] += s * gain
    end
  end

  def self.render(bpm:, bars:, key: 'A', mode: :phrygian, seq_notes: 5, seq_steps: 5, reverb: true,
                   sonitex: :heavy, nastyvcs: true)
    scale = mode == :locrian ? Modes::LOCRIAN : Modes::PHRYGIAN
    sequence = HypnoticSequence.build(root_pc: Theory.pitch_class(key), scale: scale, length: seq_notes)

    samples_per_beat = SAMPLE_RATE * 60.0 / bpm
    samples_per_step = samples_per_beat / 4.0
    total_steps = bars * STEPS_PER_BAR
    total_samples = (total_steps * samples_per_step).ceil + (SAMPLE_RATE * 2)

    kick_buffer = Array.new(total_samples, 0.0)
    seq_buffer = Array.new(total_samples, 0.0)
    perc_buffer = Array.new(total_samples, 0.0)
    rumble_buffer = Array.new(total_samples, 0.0)
    kick_onsets = []

    schedule = TechnoArrangement.schedule(bars)
    seq_note_idx = 0

    total_steps.times do |global_step|
      bar_i = global_step / STEPS_PER_BAR
      step_in_bar = global_step % STEPS_PER_BAR
      t_sample = (global_step * samples_per_step).round
      tension = TechnoArrangement.tension(bar_i, bars)

      if step_in_bar % 4 == 0 && bar_i >= schedule[:kick_start]
        mix_into(kick_buffer, Synth.techno_kick, t_sample, 1.0)
        kick_onsets << t_sample
      end

      if step_in_bar.even?
        mix_into(perc_buffer, Synth.hihat(0.05), t_sample + rand(-30..30), 0.25 + (tension * 0.15))
      end

      if (global_step % seq_steps).zero?
        cutoff = 300 + (3500 * tension)
        note_duration = (samples_per_step * seq_steps / SAMPLE_RATE) * 0.9
        midi = sequence[seq_note_idx % sequence.size]
        snd = Synth.sequence_voice(Theory.midi_to_freq(midi), note_duration, cutoff_hz: cutoff, drive: 1.4 + (tension * 0.8))
        mix_into(seq_buffer, snd, t_sample, 0.7)

        if bar_i >= schedule[:second_voice_start]
          midi2 = sequence[(seq_note_idx + 2) % sequence.size] + 12
          snd2 = Synth.sequence_voice(Theory.midi_to_freq(midi2), note_duration, cutoff_hz: cutoff * 1.4, drive: 1.6)
          mix_into(seq_buffer, snd2, t_sample, 0.4)
        end

        seq_note_idx += 1
      end

      if bar_i >= schedule[:percussion_start] && (global_step % 3 == 1)
        mix_into(perc_buffer, Synth.metallic_hit, t_sample, 0.3 + (tension * 0.2))
      end

      if bar_i >= schedule[:rumble_swell_start] && step_in_bar.zero?
        mix_into(rumble_buffer, Synth.rumble(duration_s: (samples_per_beat * 4 / SAMPLE_RATE) * 1.5), t_sample,
                 0.3 + (tension * 0.4))
      end
    end

    Texture.sidechain_duck!(seq_buffer, kick_onsets, depth: 0.85, release_ms: 220)
    Texture.sidechain_duck!(rumble_buffer, kick_onsets, depth: 0.5, release_ms: 300)

    kick_buffer = Distortion.chain(kick_buffer, stages: 3, drive: 1.6)
    seq_buffer = Distortion.chain(seq_buffer, stages: 1, drive: 1.35)
    perc_buffer = Distortion.chain(perc_buffer, stages: 3, drive: 1.7)
    perc_buffer = Texture.bitcrush(perc_buffer, bits: 7, downsample: 3)
    perc_buffer = Texture.echo(perc_buffer, delay_ms: 180, feedback: 0.42, mix: 0.32)
    rumble_buffer = reverb ? Texture.reverb(rumble_buffer, mix: 0.35) : rumble_buffer

    mixed = Array.new(total_samples) { |i| kick_buffer[i] + seq_buffer[i] + perc_buffer[i] + rumble_buffer[i] }
    mixed = Texture.reverb(mixed, mix: 0.12) if reverb

    mixed = TechnoMaster.soft_knee_compress(mixed)
    mixed = Sonitex.process(mixed, sonitex)
    mixed = NastyVCS.summing_glue(mixed) if nastyvcs
    mixed = TechnoMaster.normalize(mixed)

    [mixed, { sequence: sequence, schedule: schedule }]
  end
end

# ===========================================================================
# CLI — dispatched by mode (first ARGV token)
# ===========================================================================
if __FILE__ == $PROGRAM_NAME
  mode = ARGV.shift

  case mode
  when 'hiphop'
    options = {
      bpm: nil, bars: 16, output: 'hiphop.wav', progression: :los_angeles, key: 'Bb', producer: :dilla,
      voicing: nil, master: nil, pad_voice: :strings, seed: nil, spectrogram: false
    }

    master_names = %w[dilla_butter warm_tape lofi_dream analog_lush vinyl_worn sp1200_authentic flylo_cosmic jneiro_texture off]
    progression_names = %w[los_angeles time_donut how_does_it_feel voodoo_vamp backdoor_gospel lament_dark
                            dilla_life hiphop_dark_epic industrial_techno_dilla erykah_badu_on_and_on
                            ii_V_I vi_circle pop_jazz chromatic_drift]

    OptionParser.new do |o|
      o.banner = 'Usage: ruby dilla.rb hiphop [options]'
      o.on('--bpm N', Integer, "Tempo (defaults to the progression's native tempo, else 86)") { |v| options[:bpm] = v }
      o.on('--bars N', Integer, 'Total bars (default 16)') { |v| options[:bars] = v }
      o.on('--output PATH', 'Output WAV path') { |v| options[:output] = v }
      o.on('--progression NAME', progression_names, progression_names.join('|')) { |v| options[:progression] = v.to_sym }
      o.on('--key NAME', 'Key root, e.g. C, F, Bb (ignored for absolute progressions)') { |v| options[:key] = v }
      o.on('--producer NAME', %w[dilla flylo madlib], 'Micro-timing feel: dilla|flylo|madlib') { |v| options[:producer] = v.to_sym }
      o.on('--voicing NAME', %w[spread quartal], "spread|quartal (defaults to the progression's recommendation)") do |v|
        options[:voicing] = v.to_sym
      end
      o.on('--master NAME', master_names, "Mastering chain (defaults to the progression's evidence-cited fx): #{master_names.join('|')}") { |v| options[:master] = v.to_sym }
      o.on('--pad-voice NAME', %w[oberheim minimoog strings ambient cs80],
           'Chord pad instrument: oberheim|minimoog|strings|ambient|cs80 (default strings)') { |v| options[:pad_voice] = v.to_sym }
      o.on('--seed N', Integer, 'RNG seed for reproducible humanization') { |v| options[:seed] = v }
      o.on('--wild', 'Enable experimental flanger/phaser/echo FX on random notes/hits (off by default)') { WildFX.enabled = true }
      o.on('--spectrogram', 'Also write a .png spectrogram next to the output WAV') { options[:spectrogram] = true }
    end.parse!(ARGV)

    srand(options[:seed]) if options[:seed]
    options[:bpm] ||= Theory.suggested_bpm(options[:progression]) || 86

    buffer, meta = HiphopTrackBuilder.render(**options.reject { |k, _| %i[output seed spectrogram].include?(k) })
    SoxShell.write_wav(options[:output], buffer)

    if options[:spectrogram]
      png_path = options[:output].sub(/\.wav$/i, '.png')
      SoxShell.run("#{options[:output]} -n spectrogram -o #{png_path} -t #{options[:progression]}")
      puts "Wrote #{png_path}"
    end

    puts "Wrote #{options[:output]} — #{options[:bpm]} BPM, #{options[:bars]} bars, " \
         "#{(buffer.size / SAMPLE_RATE.to_f).round(1)}s, producer feel: #{options[:producer]}, " \
         "master: #{options[:master] || Theory.recommended_fx(options[:progression])}"
    puts "Progression (#{options[:progression]}, #{options[:voicing] || Theory.recommended_voicing(options[:progression])} voicing): " \
         "#{meta[:chord_names].join(' -> ')}"
    puts "Sections: #{meta[:sections].chunk { |s| s }.map { |name, g| "#{name}(#{g.size})" }.join(' -> ')}"

  when 'techno'
    options = {
      bpm: 132, bars: 32, output: 'techno.wav', key: 'A', mode: :phrygian,
      seq_notes: 5, seq_steps: 5, reverb: true, sonitex: :heavy, nastyvcs: true, seed: nil
    }

    OptionParser.new do |o|
      o.banner = 'Usage: ruby dilla.rb techno [options]'
      o.on('--bpm N', Integer, 'Tempo (default 132)') { |v| options[:bpm] = v }
      o.on('--bars N', Integer, 'Total bars (default 32)') { |v| options[:bars] = v }
      o.on('--output PATH', 'Output WAV path') { |v| options[:output] = v }
      o.on('--key NAME', 'Root note, e.g. A, E, C (default A)') { |v| options[:key] = v }
      o.on('--mode NAME', %w[phrygian locrian], 'phrygian|locrian') { |v| options[:mode] = v.to_sym }
      o.on('--seq-notes N', Integer, 'Hypnotic cell length, 3-6 (default 5)') { |v| options[:seq_notes] = v }
      o.on('--seq-steps N', Integer, '16th-steps per cell note — the polyrhythm ratio against 4/4 (default 5)') do |v|
        options[:seq_steps] = v
      end
      o.on('--sonitex NAME', %w[donuts_soul heavy off], 'Mastering character: donuts_soul|heavy|off (default heavy)') { |v| options[:sonitex] = v.to_sym }
      o.on('--no-nastyvcs', 'Disable the console-glue (parallel comp + bloom + tilt EQ) stage') { options[:nastyvcs] = false }
      o.on('--seed N', Integer, 'RNG seed for reproducible humanization') { |v| options[:seed] = v }
      o.on('--no-reverb', 'Disable reverb') { options[:reverb] = false }
    end.parse!(ARGV)

    srand(options[:seed]) if options[:seed]

    buffer, meta = TechnoTrackBuilder.render(**options.reject { |k, _| %i[output seed].include?(k) })
    SoxShell.write_wav(options[:output], buffer)

    puts "Wrote #{options[:output]} — #{options[:bpm]} BPM, #{options[:bars]} bars, " \
         "#{(buffer.size / SAMPLE_RATE.to_f).round(1)}s, #{options[:mode]} in #{options[:key]}"
    puts "Hypnotic cell (#{options[:seq_notes]} notes, #{options[:seq_steps]}-step polyrhythm): #{meta[:sequence].join(', ')}"
    puts "Layer entries (bars): kick #{meta[:schedule][:kick_start]}, percussion #{meta[:schedule][:percussion_start]}, " \
         "2nd voice #{meta[:schedule][:second_voice_start]}, rumble swell #{meta[:schedule][:rumble_swell_start]}"

  else
    warn 'Usage: ruby dilla.rb <hiphop|techno> [options]  (--help after the mode for details)'
    exit 1
  end
end
