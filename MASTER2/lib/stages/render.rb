# frozen_string_literal: true

module MASTER
  module Stages
    # Depressure Tank: Multi-model output refinement
    class Render
      include Dry::Monads[:result]

      CODE_FENCE = /^```/

      def call(input)
        # Get the text to render (prefer response, fallback to text)
        text = input.fetch(:response) { input.fetch(:text) { input.fetch(:original_text, "") } }

        # Apply typesetting to prose, preserve code blocks
        typeset_text = typeset(text)

        # TODO: Implement multi-model refinement
        # TODO: Apply additional Strunk & White rules (active voice)

        # Format cost/token summary if available
        summary = format_summary(input)

        enriched = input.merge(
          rendered: typeset_text,
          summary: summary
        )

        Success(enriched)
      end

      private

      def typeset(text)
        regions = []
        current = []
        in_code = false

        text.each_line do |line|
          if line.match?(CODE_FENCE)
            regions << { text: current.join, code: in_code } unless current.empty?
            current = [line]
            in_code = !in_code
            unless in_code
              regions << { text: current.join, code: true }
              current = []
            end
          else
            current << line
          end
        end
        regions << { text: current.join, code: in_code } unless current.empty?

        regions.map { |r| r[:code] ? r[:text] : prettify(r[:text]) }.join
      end

      def prettify(text)
        # Apply typography rules from Bringhurst
        text.gsub(/"([^"]*?)"/) { "\u201C#{$1}\u201D" }      # Smart quotes
            .gsub(/\s--\s/, " \u2014 ")                      # Em dashes
            .gsub(/\.\.\./, "\u2026")                        # Ellipses
      end

      def format_summary(input)
        parts = []

        if input[:tokens_in] && input[:tokens_out]
          parts << "Tokens: #{input[:tokens_in]} in, #{input[:tokens_out]} out"
        end

        if input[:model]
          parts << "Model: #{input[:model]}"
        end

        if input[:consensus_score]
          parts << "Consensus: #{(input[:consensus_score] * 100).round}%"
        end

        parts.empty? ? nil : parts.join(" | ")
      end
    end
  end
end
