# frozen_string_literal: true

module Master
  module Scan
    module Rules
      class GodClassRule < Rule
        THRESHOLD = 200

        def initialize
          super
          @id          = "god_class"
          @description = "Classes over #{THRESHOLD} lines should be split by responsibility"
          @severity    = :warning
          @axiom_tags  = [:SIMPLEST_WORKS]
        end

        def check(code, path:)
          return [] unless path.end_with?(".rb")
          lines = code.lines.size
          return [] if lines <= THRESHOLD

          class_name = code.match(/class (\w+)/i)&.[](1) || File.basename(path, ".rb")
          [finding(
            line: 1,
            message: "#{class_name} is #{lines} lines (threshold: #{THRESHOLD}) — split by responsibility"
          )]
        end
      end
    end
  end
end
