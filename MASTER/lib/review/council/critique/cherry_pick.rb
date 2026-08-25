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
          LIMIT = 12

          module_function

          # `ideation_result` arrives as a Result, a Hash, or a bare String
          # depending on which ideation path ran, hence the shape probing.
          def call(feedback, ideation_result)
            rank(feedback, ideas_text(ideation_result))
          end

          def ideas_text(ideation_result)
            return ideation_result.to_s unless ideation_result.respond_to?(:value)

            value = ideation_result.value
            value.is_a?(Hash) ? value.fetch(:final, "").to_s : value.to_s
          end

          # An errored ideation contributes nothing rather than leaking its
          # error message into the report as if it were an idea.
          def ideation_value(ideation_result)
            return "" if ideation_result.respond_to?(:err?) && ideation_result.err?

            ideation_result.respond_to?(:value) ? ideation_result.value : ideation_result
          end

          def rank(feedback, ideas_text)
            feedback_text = Array(feedback).map { |item| item[:feedback].to_s }.join("\n")
            lines = ideas_text.to_s.lines.map(&:strip).reject(&:empty?)
            lines.sort_by { |line| -text_overlap(line, feedback_text) }.first(LIMIT)
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
