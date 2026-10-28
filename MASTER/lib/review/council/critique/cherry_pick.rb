# frozen_string_literal: true

require "set"

module Master
  module Review
    module Council
      class Critique
        # Ranks the ideation output against what the panel actually complained
        # about, keeping the ideas that overlap most with the critique.
        #
        # Pure text ranking with no council state, so it lived in Critique only
        # by proximity. Out here it is directly testable.
        module CherryPick
          # A council round reviews at most twelve issues. Three materially
          # distinct options per issue leave every issue with a real choice.
          PER_ISSUE_LIMIT = 3
          LIMIT = 36
          SIMILARITY_THRESHOLD = 0.85
          ISSUE_RE = /\b(?:issue|critique|finding)\s*(\d+)\b/i.freeze
          HEADING_RE = /\A(?:solution|idea|proposal)s?\s*:?\s*\z/i.freeze
          PATH_RE = %r{\b(?:MASTER|RAILS|OPENBSD|STUDIO)/[A-Za-z0-9_./-]+}.freeze
          LINE_RE = /\b(?:line|ln)\s*#?\s*(\d+)\b/i.freeze
          SYMBOL_RE = /\b(?:class|module|def)\s+([A-Za-z_]\w*[!?=]?)/i.freeze

          module_function

          # `ideation_result` arrives as a Result, a Hash, or a bare String
          # depending on which ideation path ran, hence the shape probing.
          def call(feedback, ideation_result)
            rank(feedback, ideas_text(ideation_result))
          end

          # An errored ideation proposes nothing: its to_s is the error message.
          def ideas_text(ideation_result)
            return "" if ideation_result.respond_to?(:err?) && ideation_result.err?
            return ideation_result.to_s unless ideation_result.respond_to?(:value)

            value = ideation_result.value
            if value.is_a?(Hash)
              ideas = Array(value[:ideas]).map(&:to_s)
              final = value[:final].to_s
              (ideas + [final]).reject(&:empty?).join("\n")
            else
              value.to_s
            end
          end

          # An errored ideation contributes nothing rather than leaking its
          # error message into the report as if it were an idea.
          def ideation_value(ideation_result)
            return "" if ideation_result.respond_to?(:err?) && ideation_result.err?

            ideation_result.respond_to?(:value) ? ideation_result.value : ideation_result
          end

          # Rank inside each issue, retain three meaningfully different options,
          # then put one winner from every issue before filling remaining slots.
          # Alternatives stay alternatives; they are not separate defects to apply.
          def rank(feedback, ideas_text)
            by_issue = feedback_by_issue(feedback)
            all_feedback = Array(feedback).map { |item| item[:feedback].to_s }.join("\n")
            groups = proposals(ideas_text).group_by { |line| proposal_group(line) }
            ranked_groups = groups.sort_by { |key, _lines| group_order(key) }.to_h do |key, lines|
              issue_id = key[/\Aissue:(\d+)\z/, 1]
              query = issue_id ? by_issue.fetch(issue_id, all_feedback) : all_feedback
              ranked = lines.each_with_index
                .sort_by { |line, index| [-text_overlap(line, query), index] }
                .map(&:first)
              [key, materially_distinct(ranked).first(PER_ISSUE_LIMIT)]
            end
            winners = ranked_groups.values.filter_map(&:first)
            alternatives = ranked_groups.values.flat_map { |lines| lines.drop(1) }
            (winners + alternatives).uniq.first(LIMIT)
          end

          # The clean-tree improvement lane must apply one winner per issue or
          # anchored opportunity. The violation lane keeps alternatives for the
          # separate source-code candidate tournament.
          def one_per_issue(picks)
            seen = Set.new
            Array(picks).map(&:to_s).map(&:strip).reject(&:empty?).each_with_object([]) do |line, selected|
              key = proposal_group(line)
              next if seen.include?(key)

              seen << key
              selected << line
            end
          end

          def proposals(ideas_text)
            ideas_text.to_s.lines.map(&:strip).reject { |line| line.empty? || line.match?(HEADING_RE) }
          end

          def proposal_group(line)
            issue = line[ISSUE_RE, 1]
            return "issue:#{issue}" if issue

            path = line[PATH_RE]
            return "unlabelled" unless path

            anchor = line[LINE_RE, 1] || line[SYMBOL_RE, 1]
            anchor ? "anchor:#{path}:#{anchor}" : "path:#{path}"
          end

          def group_order(key)
            match = key.match(/\Aissue:(\d+)\z/)
            match ? [0, match[1].to_i] : [1, key]
          end

          def feedback_by_issue(feedback)
            seen = {}
            Array(feedback).reject { |item| item[:persona].to_s == "Judge" }.filter_map do |item|
              text = item[:feedback].to_s
              summary = text.lines.map(&:strip).find { |line| !line.empty? }.to_s
              next if summary.empty? || seen.key?(summary)

              seen[summary] = true
              text
            end.first(12).each_with_index.to_h { |text, index| [(index + 1).to_s, text] }
          end

          def materially_distinct(lines)
            lines.each_with_object([]) do |line, selected|
              next if selected.any? { |kept| text_overlap(line, kept) >= SIMILARITY_THRESHOLD }

              selected << line
            end
          end

          # Jaccard-ish overlap normalized by the larger side, so a long idea
          # cannot score highly by containing many words.
          def text_overlap(one, other)
            words_one = one.downcase.scan(/\w+/).to_set
            words_other = other.downcase.scan(/\w+/).to_set
            return 0.0 if words_one.empty? || words_other.empty?

            (words_one & words_other).size.to_f / [words_one.size, words_other.size].max
          end
        end
      end
    end
  end
end
