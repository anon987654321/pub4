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

      # [proposals, dropped] for an answer, checked against the paths the tree holds.
      def parse(answer, known_paths)
        lines = answer.lines.select { |line| line.strip.upcase.start_with?("PROPOSE:") }
        parsed = lines.map { |line| proposal_from(line, known_paths) }
        [parsed.compact.first(MAX), parsed.count(nil)]
      end

      def proposal_from(line, known_paths)
        kind, paths, law, reason = line.split(":", 2).last.to_s.split("|", 4).map(&:strip)
        names = paths.to_s.split(",").map { |name| name.strip.chomp("/") }.reject(&:empty?)
        return unless sound?(kind, names, known_paths)

        Proposal.new(kind: kind.downcase, paths: names, law: law_id(law),
                     reason: reason.to_s.byteslice(0, MAX_FIELD_BYTES))
      end

      def sound?(kind, names, known_paths)
        KINDS.include?(kind.to_s.downcase) && !names.empty? && names.all? { |name| known_paths.include?(name) }
      end

      def law_id(text)
        id = text.to_s.upcase
        id.empty? || id == "NONE" ? nil : id
      end
    end
  end
end
