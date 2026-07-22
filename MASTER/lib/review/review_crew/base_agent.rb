# frozen_string_literal: true

module Master
  module Review
    class ReviewCrew
      class BaseAgent
        attr_reader :name, :findings

        def initialize(name:)
          @name = name
          @findings = []
        end

        def analyze(code, file_path)
          raise NotImplementedError, "#{self.class}#analyze not implemented"
        end

        def add_finding(severity:, category:, message:, line:, suggestion:, file_path:)
          @findings << Finding.new(
            agent: name,
            severity:,
            category:,
            message:,
            line:,
            suggestion:,
            file: file_path,
          )
        end
      end
    end
  end
end
