# frozen_string_literal: true

require_relative 'base_agent'

module MASTER
  module Agents
    class ArchitectureAgent < BaseAgent
      def analyze(code, file_path = nil)
        clear_findings

        class_count = code.scan(/^\s*class\s+/).size
        module_count = code.scan(/^\s*module\s+/).size
        require_count = code.scan(/^\s*require(_relative)?\s+/).size

        if class_count + module_count > 3
          add_finding(
            severity: :medium,
            category: :architecture,
            message: "Many class/module definitions (#{class_count + module_count}) in one file",
            suggestion: "Consider splitting responsibilities into separate files"
          )
        end

        if require_count > 6
          add_finding(
            severity: :low,
            category: :architecture,
            message: "High dependency count (#{require_count}) in #{file_path || 'file'}",
            suggestion: "Review dependencies and split into smaller components"
          )
        end

        @findings
      end
    end
  end
end
