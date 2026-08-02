# frozen_string_literal: true

# Theory-grounded progression scoring -- the harmonic counterpart to
# DillaGrooveScore (rhythm). Every metric here is derived from voice-leading/
# functional-harmony theory (see lib/theory_runtime.rb's own operators:
# common-tone retention, contrary motion, circle-of-fifths bias), not from
# similarity to any named track or producer. Mirrors DillaGrooveScore's shape
# (analyze -> {score:, breakdown:}) so both can feed the same report/recommend
# pipeline.
module DillaHarmonyScore
  module_function

  def analyze(pads)
    chords = Array(pads).select { |c| c.is_a?(Hash) && c[:hz]&.any? }
    return { score: 70, breakdown: {} } if chords.length < 2

    transitions = chords.each_cons(2).map { |a, b| transition_metrics(a, b) }

    vl = transitions.map { |t| t[:voice_leading_semitones] }
    ct = transitions.map { |t| t[:common_tone_ratio] }
    contrary = transitions.count { |t| t[:contrary_motion] }
    strong_root = transitions.count { |t| t[:strong_root_motion] }
    spreads = chords.map { |c| chord_span_semitones(c) }

    avg_vl = vl.sum / vl.length
    avg_ct = ct.sum / ct.length
    contrary_ratio = contrary.to_f / transitions.length
    strong_root_ratio = strong_root.to_f / transitions.length
    spread_var = variance(spreads)

    # Smoother average voice-leading movement scores higher (Bach-style
    # stepwise preference), but zero movement (static chords) isn't "smooth,"
    # it's dead -- 1-3 semitones/voice is the actual "smooth" band.
    score = 60.0
    score += smoothness_points(avg_vl)
    score += [avg_ct * 20, 16].min
    score += 8 if contrary_ratio.between?(0.2, 0.7)
    score += 6 if strong_root_ratio.between?(0.25, 0.75)
    score -= 6 if spread_var > 30 # register discipline: chords shouldn't randomly leap span

    breakdown = {
      avg_voice_leading_semitones: avg_vl.round(3),
      avg_common_tone_ratio: avg_ct.round(3),
      contrary_motion_ratio: contrary_ratio.round(3),
      strong_root_motion_ratio: strong_root_ratio.round(3),
      register_spread_variance: spread_var.round(3),
      transitions: transitions.length,
    }

    { score: score.round.clamp(30, 98), breakdown: }
  end

  def transition_metrics(a, b)
    a_notes = Array(a[:hz]).map { |hz| DillaHarmony.hz_to_midi(hz.to_f).round }.sort
    b_notes = Array(b[:hz]).map { |hz| DillaHarmony.hz_to_midi(hz.to_f).round }.sort
    {
      voice_leading_semitones: voice_leading_distance(a_notes, b_notes),
      common_tone_ratio: common_tone_ratio(a_notes, b_notes),
      contrary_motion: contrary_motion?(a_notes, b_notes),
      strong_root_motion: strong_root_motion?(a_notes, b_notes),
    }
  end

  # Nearest-neighbor voice pairing (not fixed SATB index -- chord voicings
  # here don't guarantee equal voice counts), average movement per matched pair.
  def voice_leading_distance(a_notes, b_notes)
    return 0.0 if a_notes.empty? || b_notes.empty?

    a_notes.sum { |n| b_notes.map { |m| (m - n).abs }.min }.to_f / a_notes.length
  end

  def common_tone_ratio(a_notes, b_notes)
    return 0.0 if a_notes.empty? || b_notes.empty?

    a_pc = a_notes.map { |n| n % 12 }.uniq
    b_pc = b_notes.map { |n| n % 12 }.uniq
    shared = (a_pc & b_pc).length
    shared.to_f / [a_pc.length, b_pc.length].min
  end

  def contrary_motion?(a_notes, b_notes)
    return false if a_notes.empty? || b_notes.empty?

    bass_delta = b_notes.min - a_notes.min
    top_delta = b_notes.max - a_notes.max
    bass_delta != 0 && top_delta != 0 && (bass_delta <=> 0) != (top_delta <=> 0)
  end

  # Root motion of a 4th/5th (5 or 7 semitones, either direction) is the
  # circle-of-fifths functional-harmony backbone theory_runtime.rb's own
  # header already names as a goal; reuse DillaHarmony's canonical root
  # detection (bass note) rather than a separate implementation.
  def strong_root_motion?(a_notes, b_notes)
    return false if a_notes.empty? || b_notes.empty?

    interval = (b_notes.min - a_notes.min).abs % 12
    [5, 7].include?(interval)
  end

  def chord_span_semitones(chord)
    notes = Array(chord[:hz]).map { |hz| DillaHarmony.hz_to_midi(hz.to_f) }
    return 0.0 if notes.empty?

    notes.max - notes.min
  end

  def smoothness_points(avg_vl)
    case avg_vl
    when 0...1 then 4.0 # near-static -- some credit, but not the max
    when 1...3 then 14.0 # the actual "smooth voice-leading" band
    when 3...5 then 8.0
    else [14.0 - (avg_vl - 5), 0].max
    end
  end

  def variance(values)
    return 0.0 if values.length < 2

    mean = values.sum / values.length
    values.sum { |v| (v - mean)**2 } / values.length
  end
end
