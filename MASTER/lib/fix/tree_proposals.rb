# frozen_string_literal: true

module Master
  module Fix

    # Reads the model's answer to the first read of the tree into proposals. A line that does not
    # parse, names an unknown kind, or names a path the tree does not hold is counted and dropped:
    # a model that invents a path has not read the tree.
    module TreeProposals
      KINDS = %w[move merge delete rename split keep].freeze
      MAX = 12
      MAX_FIELD_BYTES = 400

      Proposal = Data.define(:kind, :paths, :law, :reason)

      module_function

      # A reading of an answer: the header word that starts a line, the kinds it may carry and, when
      # given, the law ids that exist. A law id outside `laws` is not a Law and is cleared.
      Dialect = Struct.new(:header, :kinds, :laws)
      FIRST_READ = Dialect.new("PROPOSE", KINDS, nil)

      # [proposals, dropped] for an answer, checked against the paths the tree holds.
      def parse(answer, known_paths, dialect = FIRST_READ)
        lines = answer.lines.select { |line| line.strip.upcase.start_with?("#{dialect.header}:") }
        parsed = lines.map { |line| proposal_from(line, known_paths, dialect) }
        [parsed.compact.first(MAX), parsed.count(nil)]
      end

      def proposal_from(line, known_paths, dialect = FIRST_READ)
        kind, paths, law, reason = line.split(":", 2).last.to_s.split("|", 4).map(&:strip)
        names = names_from(paths)
        return unless sound?(kind, names, known_paths, dialect.kinds)

        Proposal.new(kind: kind.downcase, paths: names, law: law_id(law, dialect.laws),
                     reason: reason.to_s.byteslice(0, MAX_FIELD_BYTES))
      end

      def names_from(paths) = paths.to_s.split(",").map { |name| name.strip.chomp("/") }.reject(&:empty?)

      def sound?(kind, names, known_paths, kinds = KINDS)
        kinds.include?(kind.to_s.downcase) && !names.empty? && names.all? { |name| known_paths.include?(name) }
      end

      def law_id(text, laws = nil)
        id = text.to_s.upcase
        id.empty? || id == "NONE" || (laws && !laws.include?(id)) ? nil : id
      end
    end
  end
end
