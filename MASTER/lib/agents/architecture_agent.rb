# frozen_string_literal: true

require_relative 'base_agent'

module MASTER
  module Agents
    class ArchitectureAgent < BaseAgent
      CLASS_PATTERN = /^\s*class\s+/.freeze
      MODULE_PATTERN = /^\s*module\s+/.freeze
      REQUIRE_PATTERN = /^\s*require(_relative)?\s+/.freeze
      MAX_DEFINITIONS = 3
      MAX_REQUIRE_COUNT = 6

      def analyze(code, file_path = nil)
        clear_findings

        class_count = code.scan(CLASS_PATTERN).size
        module_count = code.scan(MODULE_PATTERN).size
        require_count = code.scan(REQUIRE_PATTERN).size

        if class_count + module_count > MAX_DEFINITIONS
          add_finding(
            severity: :medium,
            category: :architecture,
            message: "Many class/module definitions (#{class_count + module_count}) in one file",
            suggestion: "Consider splitting responsibilities into separate files"
          )
        end

        if require_count > MAX_REQUIRE_COUNT
          add_finding(
            severity: :low,
            category: :architecture,
            message: "High dependency count (#{require_count}) in #{file_path || 'unknown file'}",
            suggestion: "Review dependencies and split into smaller components"
          )
        end

        @findings
      end
    end
  end
end
