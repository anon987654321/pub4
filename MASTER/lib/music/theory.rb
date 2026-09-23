# frozen_string_literal: true

module Master
  module Music
    # Small music-theory core: scales, chords, progressions.
    module Theory
      NOTE_NAMES = %w[C C# D D# E F F# G G# A A# B].freeze
      SCALES = {
        major: [0, 2, 4, 5, 7, 9, 11],
        minor: [0, 2, 3, 5, 7, 8, 10],
        dorian: [0, 2, 3, 5, 7, 9, 10],
        phrygian: [0, 1, 3, 5, 7, 8, 10],
        lydian: [0, 2, 4, 6, 7, 9, 11],
        mixolydian: [0, 2, 4, 5, 7, 9, 10],
        locrian: [0, 1, 3, 5, 6, 8, 10],
        harmonic_minor: [0, 2, 3, 5, 7, 8, 11],
        melodic_minor: [0, 2, 3, 5, 7, 9, 11],
      }.freeze

      QUALITIES = {
        major: [0, 4, 7],
        minor: [0, 3, 7],
        dominant7: [0, 4, 7, 10],
        minor7: [0, 3, 7, 10],
        major7: [0, 4, 7, 11],
        half_diminished: [0, 3, 6, 10],
        diminished: [0, 3, 6],
      }.freeze

      PROGRESSIONS = {
        dilla_love: %w[i7 iv7 bVII7 bVI7],
        neo_soul_loop: %w[i7 iv7 bVII7 bVI7],
        techno_pulse: %w[i i bVI bVII],
        jazz_loop: %w[ii7 V7 I7 vi7],
        modal_drift: %w[i7 III7 bVII7 iv7],
      }.freeze

      module_function

      def note_index(note)
        note = note.to_s
        index = NOTE_NAMES.index(note)
        return index if index

        index = NOTE_NAMES.index(note[0].upcase + note[1].to_s)
        index
      end

      def scale(root: "C", name: :major)
        base = note_index(root) || 0
        SCALES.fetch(name.to_sym).map do |offset|
          NOTE_NAMES[(base + offset) % 12]
        end
      end

      def chord(root: "C", quality: :minor7)
        base = note_index(root) || 0
        QUALITIES.fetch(quality.to_sym).map do |offset|
          NOTE_NAMES[(base + offset) % 12]
        end
      end

      def progression(root: "C", name: :dilla_love, scale: :minor)
        symbols = PROGRESSIONS.fetch(name.to_sym)
        base = note_index(root) || 0
        symbols.map { |symbol| chord_from_symbol(symbol, base) }
      end

      module_function

      def chord_from_symbol(symbol, base)
        quality = if symbol.include?("7")
                    symbol.include?("m") || symbol.match?(/\Ai7/) ? :minor7 : :dominant7
                  elsif symbol.include?("m")
                    :minor
                  else
                    :major
                  end
        root = NOTE_NAMES[(base + degree(symbol)) % 12]
        chord(root:, quality:)
      end

      def degree(symbol)
        case symbol
        when "i7", "i", "I", "I7" then 0
        when "ii7", "ii", "II", "II7" then 2
        when "iii7", "iii", "III", "III7" then 4
        when "iv7", "iv", "IV", "IV7" then 5
        when "v7", "v", "V", "V7" then 7
        when "vi7", "vi", "VI", "VI7" then 9
        when "vii7", "vii", "VII", "VII7" then 10
        when "bVII", "bVII7" then 10
        when "bVI", "bVI7" then 8
        else 0
        end
      end
    end
  end
end
