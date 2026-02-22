# frozen_string_literal: true

module MASTER
  module Stages
    # Stage 8: Format output (typography)
    class Render
      CODE_FENCE = /^```/

      def call(input)
        text = input[:response] || ""
        Result.ok(input.merge(rendered: apply_typography(text)))
      end

      private

      def apply_typography(text)
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

        regions.map { |r| r[:code] ? r[:text] : beautify_prose(r[:text]) }.join
      end

      def beautify_prose(text)
        text
          .gsub(/"([^"]*?)"/) { "\u201C#{Regexp.last_match(1)}\u201D" }
          .gsub(/\s--\s/, " \u2014 ")
          .gsub("...", "\u2026")
      end
    end
  end
end
