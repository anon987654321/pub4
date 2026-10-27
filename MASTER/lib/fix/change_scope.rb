# frozen_string_literal: true

require_relative "unified_diff"

module Master
  module Fix

    # What one change touched, read once from git's own diff. The scope guard,
    # boyscout, the house lint, the collapse guard and the file-size laws all
    # ask it; each once kept its own idea of "changed", and a repair one of
    # them passed another refused. A hunk that only deletes covers the new
    # line it follows: a finding at the seam it leaves is the deletion's.
    class ChangeScope
      class << self
        def between(old_src, new_src)
          old_src = old_src.to_s

          new_src = new_src.to_s
          new(hunks_between(old_src, new_src), old_bytes: old_src.bytesize, new_bytes: new_src.bytesize)
        end

        # The findings a change introduced: those of a law whose count grew, less the ones that match a
        # finding that stood before by everything an edit does not move (its line and the file's
        # fingerprint). A count alone flagged every row of a grown law; an exact match alone read a
        # finding whose message carries a number ("25 lines" to "26") as new. Rows may use symbol or
        # string keys; boyscout, the new-violations summary and the priority check all ask this.
        MOVES_WITH_AN_EDIT = %w[line fingerprint].freeze

        def introduced_findings(before, after)
          standing = before.map { |row| identity(row) }.tally
          grown_laws(before, after).then { |grown| after.select { |row| grown.key?(law_of(row)) } }.reject do |row|
            key = identity(row)
            standing[key].to_i.positive? && (standing[key] -= 1)
          end
        end

        def grown_laws(before, after)
          had = before.map { |row| law_of(row) }.tally
          after.map { |row| law_of(row) }.tally.select { |law, count| count > had.fetch(law, 0) }
        end

        def law_of(row) = (row[:law] || row["law"]).to_s

        def identity(row) = row.to_h { |key, value| [key.to_s, value] }.except(*MOVES_WITH_AN_EDIT)

        # One scope per file of a multi-file `git diff -U0`, keyed by path.
        def from_diff(text) = UnifiedDiff.per_file(text).transform_values { |body| new(UnifiedDiff.hunks(body)) }

        private

        def hunks_between(old_src, new_src)
          return [] if old_src == new_src

          diff = UnifiedDiff.between(old_src, new_src)
          diff ? UnifiedDiff.hunks(diff) : [UnifiedDiff.span(old_src, new_src)]
        end
      end

      attr_reader :hunks, :old_bytes

      def initialize(hunks, old_bytes: nil, new_bytes: nil)
        @hunks = hunks.freeze
        @old_bytes = old_bytes
        @new_bytes = new_bytes
        freeze
      end

      def empty? = hunks.empty?

      def new_ranges = hunks.map(&:new_range)

      # A finding as the scanner hands it: a hash whose :line is in the new file.
      def covers?(finding)
        line = (finding[:line] || finding["line"]).to_i
        new_ranges.any? { |range| range.cover?(line) }
      end

      # Whether any hunk lands inside +range+ of the new file, as one does in a
      # method's lines when an edit anywhere in it, a deletion included, changes it.
      def touches?(range)
        new_ranges.any? { |hunk| hunk.begin <= range.end && range.begin <= hunk.end }
      end

      # Lines added minus lines removed; the file grew when this is positive.
      def line_delta = hunks.sum { |hunk| hunk.new_count - hunk.old_count }

      def grew? = line_delta.positive?

      # The new file's size as a fraction of the old; nil without the sources
      # or with an empty old file.
      def size_ratio
        return unless @old_bytes&.positive? && @new_bytes

        @new_bytes.fdiv(@old_bytes)
      end
    end
  end
end
