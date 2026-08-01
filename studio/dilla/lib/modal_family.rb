# frozen_string_literal: true

require "set"
require_relative "key_lock"

# Which progressions belong in the same rotation.
#
# The stream ran eight progressions — Dilla's own — because widening it meant
# key chaos: the catalogue spans 248 progressions across every mode, and putting
# Lydian next to Phrygian next to whole-tone has no centre. KeyLock removes that
# objection by bringing everything to one tonic, so the question becomes the
# narrower and more useful one: which progressions share a *scale*, not just a
# root.
#
# The collection is Bb Dorian/Aeolian — the bittersweet soul region, ♭3 ♭6 ♭7
# with the Dorian ♮6 available — plus the major third, because the parallel
# major is not a foreign key. Alternating Bb minor and Bb major is modal
# interchange, which is idiomatic to this music rather than a mistake; `climax`
# (Bbmaj7 Dm7 Gm7 Bb7) is Dilla's own and it is parallel major.
FAMILY_DEGREES = %w[Bb C Db D Eb F Gb G Ab].freeze

module ModalFamily
  # 0.80, chosen by measurement rather than taste. At 1.00 and 0.90 the filter
  # drops two of Dilla's eight; at 0.85 it still drops one; at 0.75 it admits 239
  # of 248 and has stopped filtering. 0.80 keeps all eight and excludes 45.
  #
  # Roots rather than full chord tones: an extension can borrow from outside the
  # collection for one chord without leaving the key, which is the whole point of
  # a borrowed dominant or a tritone sub. Where the *root* leaves, the progression
  # has actually modulated.
  THRESHOLD = 0.80

  module_function

  def enabled? = ENV.fetch("MODAL_ROTATION", "1") != "0"

  def threshold = (ENV["MODAL_THRESHOLD"] || THRESHOLD).to_f

  def collection
    @collection ||= Set.new(FAMILY_DEGREES.filter_map { |n| KeyLock::PITCH_CLASS[n] })
  end

  def roots(chords)
    Array(chords).filter_map { |c| KeyLock::SYMBOL.match(KeyLock.chord_name(c))&.[](1) }
  end

  # Fit is measured *after* the key lock, since that is the form the rotation
  # actually plays. Measuring the source keys would reject anything not already
  # in Bb, which is most of the catalogue.
  def fit(chords)
    locked = KeyLock.lock(chords)
    pcs = roots(locked).filter_map { |r| KeyLock::PITCH_CLASS[r] }
    return 0.0 if pcs.empty?

    pcs.count { |p| collection.include?(p) }.to_f / pcs.size
  end

  def compatible?(chords) = fit(chords) >= threshold

  # Memoised per progression name: the pool is rebuilt per track and the fit is a
  # pure function of a frozen table.
  def compatible_name?(name, chords)
    @cache ||= {}
    key = name.to_s
    return @cache[key] if @cache.key?(key)

    @cache[key] = compatible?(chords)
  end

  # The rotation: the given core first, then everything else in the family.
  #
  # Widened outward from the core rather than replacing it —
  # DILLA_PROGRESSIONS_ONLY narrowing to Dilla's own was a deliberate choice
  # (2026-07-27), and this keeps those eight while admitting the rest of the
  # catalogue that belongs in the same key and mode. MODAL_ROTATION=0 restores
  # the narrow pool exactly.
  # `always` names progressions that skip the fit test entirely.
  #
  # The test is diatonic: it asks what share of a progression's roots fall in one
  # nine-note collection. That is the right question for 248 catalogue entries of
  # unknown provenance, and the wrong one for a deliberate two-centre vamp, which
  # fails it by construction rather than by accident. Jamal's Pavanne locks to
  # Am7-Bbm7 and scores 0.50; So What locks to Bbm7-Bm7 and scores 0.75, both
  # under the 0.80 threshold — and a modal vamp a semitone apart is exactly the
  # device those two records are famous for.
  #
  # KeyLock already guarantees one tonal centre, so nothing here is protecting
  # against key chaos. Hand-curated, sourced progressions are therefore exempt:
  # they were chosen, and a heuristic for unvetted material should not overrule
  # that.
  def widen(core, catalogue, always: [])
    return core unless enabled?

    exempt = Array(always).map(&:to_s)
    extra = catalogue.filter_map do |name, chords|
      next if core.map(&:to_s).include?(name.to_s)
      next unless chords.is_a?(Array) && chords.size >= 2
      next unless exempt.include?(name.to_s) || compatible_name?(name, chords)

      name.to_s
    end
    (core.map(&:to_s) + extra.sort).uniq
  end
end
