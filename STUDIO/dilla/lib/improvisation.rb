# frozen_string_literal: true

# Twelve progressions the engine writes itself.
#
# The catalogue it plays is otherwise seven progressions taken off records, each
# with a date and a source. This is the other half: the same music understood
# well enough to make more of it, rather than only to quote it.
#
# Five languages, and each is a small set of rules about where a root may move
# next and what quality sits on it. That is what a style is at this level --
# not a sound, which the synthesiser decides, and not a groove, which the pocket
# decides, but a constraint on harmonic motion. Bach's is the strictest and
# Flying Lotus's is the loosest, and the difference between them is legible in
# how many roots each one allows.
#
# Every chord is emitted with explicit frequencies rather than a name to be
# looked up. The lookup keeps the FIRST entry under a name, and these are merged
# last, so a generated "Am9" would silently resolve to somebody else's voicing.
# The `imp` tag on every name follows the convention the tension chords already
# set -- Ebm7fil, E7climax, Cm11nc -- and keeps the quality parseable.
module DillaImprovisation
  # A4 = 440, MIDI 69. Everything else follows.
  def self.hz(midi) = (440.0 * (2.0**((midi - 69) / 12.0))).round(2)

  PITCH_NAMES = %w[C Db D Eb E F Gb G Ab A Bb B].freeze

  # Intervals above the root, in semitones.
  QUALITIES = {
    "maj" => [0, 4, 7],
    "min" => [0, 3, 7],
    "dim" => [0, 3, 6],
    "maj7" => [0, 4, 7, 11],
    "maj9" => [0, 4, 7, 11, 14],
    "m7" => [0, 3, 7, 10],
    "m9" => [0, 3, 7, 10, 14],
    "m11" => [0, 3, 7, 10, 17],
    "7" => [0, 4, 7, 10],
    "sus2" => [0, 2, 7],
    "sus4" => [0, 5, 7],
    "sus9" => [0, 5, 7, 10, 14],
    "add9" => [0, 4, 7, 14],
    # A quartal stack is fourths rather than thirds, so it names no mode: it is
    # the reason a Flying Lotus chord can sit under any bass note at all.
    "q4" => [0, 5, 10, 15],
    "q4b" => [0, 5, 10, 15, 20],
  }.freeze

  # Where the chords sit. Low enough to be a bed, high enough that a four-note
  # stack does not turn to mud below the bass.
  ROOT_MIDI = 50 # D3

  class << self
    # --- the five languages ------------------------------------------------
    #
    # Each returns [[root_offset_in_semitones, quality], ...] against a tonic.

    # Bach: motion by descending fifths, which is the sequence itself, with the
    # dominant suspended before it resolves. The suspension is prepared -- the
    # note held into it belongs to the chord before -- and it falls by step, the
    # only two things that make a suspension a suspension rather than a wrong
    # note. Outer voices never move in parallel fifths or octaves; the voicing
    # operators downstream enforce that, and the root motion here never asks
    # them to.
    def bach_descending_fifths
      [[0, "min"], [5, "min"], [10, "maj"], [3, "maj7"], [8, "maj"], [1, "dim"], [7, "sus4"], [0, "min"]]
    end

    def bach_suspension_chain
      [[0, "min"], [7, "sus4"], [7, "maj"], [5, "min"], [0, "sus4"], [0, "min"], [10, "maj7"], [0, "min"]]
    end

    # Grieg: a pedal underneath, and above it the mixture -- the lowered seventh
    # borrowed against the raised one, and a chromatic mediant that belongs to
    # no key the piece has been in. The motif is the signature and it is two
    # intervals: a minor second down, then a major third down. Here it is the
    # root line of the last three chords, so the tune is in the harmony rather
    # than laid over it.
    def grieg_pedal_mixture
      [[0, "m9"], [10, "add9"], [8, "maj7"], [0, "m9"], [0, "m9"], [11, "maj"], [7, "min"], [0, "m9"]]
    end

    def grieg_motif_fall
      [[0, "min"], [10, "maj"], [5, "min"], [0, "min"], [0, "min"], [11, "min"], [7, "maj7"], [0, "m9"]]
    end

    # Dilla: one quality, planed. The chords do not resolve to each other, they
    # are the same shape moved -- which is why the language survives being cut
    # out of a record and looped, and why functional analysis says nothing
    # useful about it. Slash chords over a pedal are the other half: the bass
    # stays and the harmony walks over it.
    def dilla_planing_m9
      [[0, "m9"], [-2, "m9"], [-3, "m9"], [-5, "m9"], [0, "m9"], [-2, "m9"], [-4, "m9"], [-5, "m9"]]
    end

    def dilla_maj9_walk
      [[0, "maj9"], [-1, "maj9"], [-3, "maj9"], [-4, "maj9"], [0, "maj9"], [-1, "maj9"], [2, "maj9"], [0, "maj9"]]
    end

    def dilla_slash_pedal
      [[0, "m11"], [5, "m9"], [3, "maj9"], [10, "m9"], [0, "m11"], [5, "m9"], [8, "maj9"], [0, "m11"]]
    end

    def dilla_chromatic_drop
      [[0, "m9"], [-1, "m9"], [-2, "m9"], [-3, "m9"], [-4, "m9"], [-3, "m9"], [-1, "m9"], [0, "m9"]]
    end

    # Flying Lotus: quartal stacks, so nothing names a mode; roots a major third
    # apart, which is the chromatic mediant leap and belongs to two keys at once;
    # and no return home. The last chord is deliberately not the first -- the
    # language is a refusal to resolve, and ending on the tonic would undo it.
    def flylo_quartal_mediants
      [[0, "q4"], [4, "q4"], [8, "q4b"], [4, "q4"], [-4, "q4"], [-8, "q4b"], [3, "q4"], [8, "q4"]]
    end

    def flylo_unresolved_stack
      [[0, "q4b"], [6, "q4"], [1, "q4"], [8, "q4b"], [3, "q4"], [-2, "q4"], [7, "q4b"], [6, "q4"]]
    end

    # Röyksopp: the bass does not move. Everything above it is suspended -- the
    # second and the fourth standing in for the third, so no chord commits to
    # major or minor -- and the sixth is raised, which is Dorian and is the one
    # degree separating this from ordinary minor.
    def royksopp_static_sus
      [[0, "sus2"], [0, "sus4"], [0, "m9"], [0, "sus2"], [5, "sus2"], [0, "sus4"], [10, "sus2"], [0, "m9"]]
    end

    def royksopp_dorian_lift
      [[0, "m9"], [5, "maj"], [10, "sus2"], [0, "m9"], [2, "min"], [5, "maj"], [10, "add9"], [0, "m9"]]
    end

    # The twelve, in the order a demo plays them: each language's own pieces
    # together, so a listener hears a voice rather than a shuffle.
    def languages
      {
        bach_descending_fifths: bach_descending_fifths,
        bach_suspension_chain: bach_suspension_chain,
        grieg_pedal_mixture: grieg_pedal_mixture,
        grieg_motif_fall: grieg_motif_fall,
        dilla_planing_m9: dilla_planing_m9,
        dilla_maj9_walk: dilla_maj9_walk,
        dilla_slash_pedal: dilla_slash_pedal,
        dilla_chromatic_drop: dilla_chromatic_drop,
        flylo_quartal_mediants: flylo_quartal_mediants,
        flylo_unresolved_stack: flylo_unresolved_stack,
        royksopp_static_sus: royksopp_static_sus,
        royksopp_dorian_lift: royksopp_dorian_lift,
      }
    end

    # --- realisation -------------------------------------------------------

    # The tonic each language is improvised on.
    #
    # Drawn, not fixed, because "improvised" that comes back in the same key
    # every time is a recording. Drawn from a seed and recorded, because an
    # improvisation nobody can play again is lost -- which is the same rule the
    # render seed follows. IMPROV_SEED replays a set exactly.
    def seed
      @seed ||= (ENV["IMPROV_SEED"] || ENV["DEMO_SEED"] || Random.new_seed % 1_000_000_000).to_i
    end

    def tonic_for(name)
      # Seeded on the name as well as the run, so two languages in one demo do
      # not land in the same key by accident.
      rng = Random.new(seed + name.to_s.each_char.sum(&:ord))
      # Db3 to B3. A whole octave of tonics, and none low enough to make a
      # five-note stack unreadable.
      ROOT_MIDI + rng.rand(0..11)
    end

    def chord_name(root_midi, quality)
      "#{PITCH_NAMES[root_midi % 12]}#{quality}imp"
    end

    def chord_for(root_midi, quality)
      intervals = QUALITIES.fetch(quality)
      { name: chord_name(root_midi, quality),
        hz: intervals.map { |semitones| hz(root_midi + semitones) } }
    end

    # Every distinct chord the twelve use, for the pad lookup.
    def chords
      progression_chords.values.flatten(1).uniq { |chord| chord[:name] }
    end

    # name => [chord, ...], realised once per run.
    def progression_chords
      @progression_chords ||= languages.to_h do |name, spec|
        tonic = tonic_for(name)
        [name, spec.map { |offset, quality| chord_for(tonic + offset, quality) }]
      end
    end

    # name => [chord name, ...], which is the shape CHORD_PROGRESSIONS holds.
    def progressions
      progression_chords.transform_values { |chords| chords.map { |chord| chord[:name] } }
    end

    def names = languages.keys

    # One line an operator can read back, and the seed that reproduces it.
    def report
      progression_chords.map do |name, chords|
        format("  %-24s %s", name, chords.map { |c| c[:name].sub(/imp\z/, "") }.join(" "))
      end
    end
  end
end
