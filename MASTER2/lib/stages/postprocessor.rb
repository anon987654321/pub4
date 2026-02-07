# frozen_string_literal: true

module MASTER
  module Stages
    class Postprocessor
      CODE_FENCE = /^```/

      def call(input)
        text = input[:response] || input[:text] || input[:original_text] || ""
        typeset_text = typeset_safe(text)
        summary = format_summary(input)

        enriched = input.merge(
          rendered: typeset_text,
          summary: summary
        )

        Result.ok(enriched)
      end

      private

      def typeset_safe(text)
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

        regions.map { |r| r[:code] ? r[:text] : typeset_prose(r[:text]) }.join
      end

      def typeset_prose(text)
        text.gsub(/"([^"]*?)"/) { "\u201C#{$1}\u201D" }
            .gsub(/\s--\s/, " \u2014 ")
            .gsub(/\.\.\./, "\u2026")
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
