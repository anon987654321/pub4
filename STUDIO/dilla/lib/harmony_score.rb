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

  # A chord here carries its bass separately from its upper voices:
  #
  #   { name:, hz: [upper voices], bass_hz: <the root under them>, theory: }
  #
  # Everything below used to read :hz alone and take its lowest note as the bass,
  # which is not the bass -- it is the bottom of the upper structure. The comment
  # over strong_root_motion? even said it was using the bass note while the code
  # used a_notes.min, so the instrument disagreed with its own description.
  #
  # That mattered more than a naming slip. A slash chord or an upper triad over a
  # moving root is a structure held still while the bass walks underneath, and
  # measuring it without the bass reports the opposite of what it is: the root
  # motion vanishes and the upper voices, re-voiced to stay in register, read as
  # leaps. upper_triad_tower scored worst of all 401 progressions on exactly this.
  def voices_of(chord)
    upper = Array(chord[:hz]).map { |hz| DillaHarmony.hz_to_midi(hz.to_f).round }.sort
    bass = chord[:bass_hz].to_f.positive? ? DillaHarmony.hz_to_midi(chord[:bass_hz].to_f).round : upper.first
    # Drop a duplicate of the bass out of the upper set so it is not counted as
    # both the root and a voice above it.
    [bass, upper.reject { |n| n == bass }]
  end

  def transition_metrics(a, b)
    a_bass, a_upper = voices_of(a)
    b_bass, b_upper = voices_of(b)
    a_upper = [a_bass] if a_upper.empty?
    b_upper = [b_bass] if b_upper.empty?
    {
      # Upper voices only. The bass is a separate line with its own logic; adding
      # its movement into the average is what made held structures look like leaps.
      voice_leading_semitones: voice_leading_distance(a_upper, b_upper),
      root_motion_semitones: ((b_bass - a_bass).abs % 12).to_f,
      common_tone_ratio: common_tone_ratio(a_upper, b_upper),
      contrary_motion: contrary_motion?(a_bass, a_upper, b_bass, b_upper),
      oblique_motion: oblique_motion?(a_bass, a_upper, b_bass, b_upper),
      strong_root_motion: strong_root_motion?(a_bass, b_bass),
    }
  end

  # Nearest-neighbor voice pairing (not fixed SATB index -- chord voicings here
  # don't guarantee equal voice counts), average movement per matched pair.
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

  # The real bass against the centre of the structure above it, rather than the
  # bottom and top of one stack. Two independent lines moving apart is what
  # contrary motion means; the outer notes of a single voicing moving apart is
  # usually just a re-voicing.
  def contrary_motion?(a_bass, a_upper, b_bass, b_upper)
    bass_delta = b_bass - a_bass
    upper_delta = centroid(b_upper) - centroid(a_upper)
    bass_delta != 0 && upper_delta.abs > 0.25 && (bass_delta <=> 0) != (upper_delta <=> 0)
  end

  # Oblique motion: one line moves while the other holds. This is the pedal, the
  # slash chord and the upper structure over a walking root -- the sound the old
  # scorer had no term for at all, and therefore scored as failure.
  def oblique_motion?(a_bass, a_upper, b_bass, b_upper)
    bass_moved = (b_bass - a_bass).abs >= 1
    upper_moved = (centroid(b_upper) - centroid(a_upper)).abs > 0.5
    bass_moved != upper_moved
  end

  def centroid(notes) = notes.empty? ? 0.0 : notes.sum.to_f / notes.length

  # Root motion of a 4th or 5th is the circle-of-fifths backbone. Taken from the
  # chord's own bass_hz, which is what the comment here always claimed.
  def strong_root_motion?(a_bass, b_bass)
    [5, 7].include?((b_bass - a_bass).abs % 12)
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
