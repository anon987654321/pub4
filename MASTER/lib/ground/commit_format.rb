# frozen_string_literal: true

require "yaml"

module Master
  module Ground
    # The shape of a commit message, read from data/commit_format.yml. MASTER's runtime normalises its
    # subjects with `normalize_subject`; the commit-msg hook asks `problems` of everyone else's. One
    # definition, YAML and nothing else, so a git hook runs it without booting the runtime.
    module CommitFormat
      # `feat:`, `fix(scope):`, `refactor!:` and the like.
      PREFIX = /\A(?:feat|fix|refactor|docs|test|chore|perf|style|build|ci|revert)(?:\([^)]*\))?!?:\s*/i
      TRAILER = /\A[A-Za-z][A-Za-z-]*: \S/

      module_function

      def rules(root: Master::ROOT)
        YAML.safe_load_file(File.join(root, "data", "commit_format.yml"), aliases: false)
      end

      def max_chars(root: Master::ROOT) = rules(root:).dig("subject", "max_chars")

      # MASTER's subject: no type prefix, one line of single spaces, no closing punctuation, capitalised.
      def normalize_subject(title)
        text = title.to_s.strip.sub(PREFIX, "").gsub(/\s+/, " ")
        text.sub(/[.!?]\z/, "").sub(/\A([a-z])/) { Regexp.last_match(1).upcase }
      end

      # The -m paragraphs joined by a blank line; an empty list means the message is fine.
      def problems(message, root: Master::ROOT)
        lines = message.to_s.strip.lines.map(&:chomp)
        return ["the message is empty"] if lines.empty?

        spec = rules(root:)
        [*subject_problems(lines.first, spec.fetch("subject")),
         *layout_problems(lines),
         *trailer_problems(lines, spec.fetch("trailers"))]
      end

      def subject_problems(subject, rule)
        [length_problem(subject, rule), punctuation_problem(subject, rule),
         prefix_problem(subject, rule), capital_problem(subject, rule)].compact
      end

      def length_problem(subject, rule)
        limit = rule.fetch("max_chars")
        "the subject is #{subject.size} characters, over #{limit}" if subject.size > limit
      end

      def punctuation_problem(subject, rule)
        return if rule.fetch("trailing_punctuation") || !subject.match?(/[.!?]\z/)

        "the subject ends with #{subject[-1].inspect}; a subject is a label"
      end

      def prefix_problem(subject, rule)
        return if rule.fetch("conventional_prefix") || !subject.match?(PREFIX)

        "the subject starts with a type prefix (#{subject[PREFIX].strip}); MASTER strips them"
      end

      def capital_problem(subject, rule)
        "the subject starts with a lowercase letter" if rule.fetch("capitalised") && subject.match?(/\A[a-z]/)
      end

      def layout_problems(lines)
        lines.size > 1 && !lines[1].empty? ? ["a blank line must follow the subject"] : []
      end

      def trailer_problems(lines, rule)
        return [] unless rule.fetch("required")

        paragraphs = paragraphs_of(lines)
        keys = rule.fetch("accepted_keys").map(&:downcase)
        return [] if paragraphs.size > 1 && trailer?(paragraphs.last, keys)

        ["the last paragraph must be a trailer (#{rule.fetch("accepted_keys").join(", ")}: ...)"]
      end

      def trailer?(paragraph, keys)
        paragraph.all? { |line| line.match?(TRAILER) } &&
          paragraph.any? { |line| keys.include?(line.split(":").first.downcase) }
      end

      # Blank-line separated paragraphs, each an array of lines.
      def paragraphs_of(lines)
        chunks = lines.chunk_while { |a, b| !a.empty? && !b.empty? }
        chunks.map { |chunk| chunk.reject(&:empty?) }.reject(&:empty?)
      end
    end
  end
end
