# frozen_string_literal: true

# A small deterministic composer: memory, expectation, contrast and bounded
# surprise. It does not synthesize sound and it never replaces the musical data;
# it chooses among notes the harmony has already allowed.
class DillaComposerMind
  HISTORY_LIMIT = 32
  MOTIF_WINDOW = 4
  LEAP_PENALTY = 0.045
  REPETITION_REWARD = 0.14
  NOVELTY_REWARD = 0.11

  attr_reader :note_history, :interval_history, :harmony_history

  def initialize(rng:)
    @rng = rng
    @note_history = []
    @interval_history = []
    @harmony_history = []
  end

  def observe_harmony(symbol, pitch_classes)
    @harmony_history << { symbol: symbol.to_s, pcs: Array(pitch_classes).map(&:to_i).uniq }
    @harmony_history.shift while @harmony_history.length > MOTIF_WINDOW
  end

  def choose_note(candidates:, previous:, chord_pcs:, scale_pcs:, reach:)
    pool = Array(candidates).uniq
    return previous if pool.empty?

    recent = @note_history.last(MOTIF_WINDOW)
    intervals = @interval_history.last(MOTIF_WINDOW)
    repetition = motif_repetition
    weights = pool.to_h do |note|
      score = 0.0
      distance = (note.to_i - previous.to_i).abs
      score -= distance * LEAP_PENALTY
      score += 0.22 if Array(chord_pcs).include?(note.to_i % 12)
      score += 0.07 if Array(scale_pcs).include?(note.to_i % 12)
      score += REPETITION_REWARD if recent.include?(note.to_i) && repetition > 0.55
      score += NOVELTY_REWARD if !recent.include?(note.to_i) && repetition < 0.45
      score += expectation_bonus(note.to_i, chord_pcs)
      score -= 0.13 if intervals.last && interval_used?(note.to_i, previous.to_i)
      score += @rng.rand * 0.035
      [note, score]
    end

    weights.max_by(&:last).first
  end

  def accept_note(note)
    note = note.to_i
    if (previous = @note_history.last)
      @interval_history << note - previous
      @interval_history.shift while @interval_history.length > HISTORY_LIMIT
    end
    @note_history << note
    @note_history.shift while @note_history.length > HISTORY_LIMIT
    note
  end

  def motif_repetition
    return 0.0 if @interval_history.empty?

    recent = @interval_history.last(MOTIF_WINDOW)
    return 0.0 if recent.empty?

    repeated = recent.each_cons(2).count { |a, b| a == b }
    repeated.to_f / [recent.length - 1, 1].max
  end

  def lead_probability(base)
    report = critique
    adjustment = 0.68 + (report.fetch(:score) * 0.42)
    (base.to_f * adjustment).clamp(0.0, 1.0)
  end

  def critique
    notes = @note_history
    intervals = @interval_history
    return { notes: notes.length, repetition: 0.0, leap_rate: 0.0, score: 0.0 } if notes.empty?

    leaps = intervals.count { |interval| interval.abs > 7 }
    repetition = motif_repetition
    leap_rate = leaps.to_f / [intervals.length, 1].max
    score = 1.0 - (leap_rate * 0.45) - ((repetition - 0.65).abs * 0.35)
    { notes: notes.length, repetition: repetition.round(3), leap_rate: leap_rate.round(3), score: score.clamp(0.0, 1.0).round(3) }
  end

  private

  def expectation_bonus(note, chord_pcs)
    return 0.0 if @harmony_history.length < 2

    previous = @harmony_history[-2][:pcs]
    current = Array(chord_pcs)
    entered = current - previous
    return 0.0 if entered.empty?

    entered.include?(note % 12) ? 0.12 : 0.0
  end

  def interval_used?(note, previous)
    interval = note - previous
    @interval_history.last(6).include?(interval) && @interval_history.last(6).count(interval) >= 2
  end
end
