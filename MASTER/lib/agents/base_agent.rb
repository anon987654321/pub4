# frozen_string_literal: true

require 'time'

module MASTER
  module Agents
    class BaseAgent
      attr_reader :name, :findings

      def initialize(llm:, principles: [])
        @llm = llm
        @principles = principles
        @findings = []
        @name = self.class.name.split("::").last
      end

      # Abstract method - to be implemented by subclasses
      def analyze(code, file_path = nil)
        raise NotImplementedError, "Subclasses must implement #analyze"
      end

      protected

      def add_finding(severity:, category:, message:, line: nil, suggestion: nil)
        @findings << {
          agent: @name,
          severity: severity,  # :critical, :high, :medium, :low, :info
          category: category,
          message: message,
          line: line,
          suggestion: suggestion,
          timestamp: Time.now.iso8601
        }
      end

      def analyze_with_llm(prompt, tier: :fast)
        result = @llm.chat(prompt, tier: tier)
        result.ok? ? result.value : nil
      end

      def clear_findings
        @findings = []
      end
    end
  end
end
