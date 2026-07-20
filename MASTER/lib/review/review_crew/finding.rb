# frozen_string_literal: true

module Master
  module Review
    class ReviewCrew
      Finding = Struct.new(:agent, :severity, :category, :message, :line, :suggestion, :file, keyword_init: true) do
        def to_h
          {
            agent: agent,
            severity: severity,
            category: category,
            message: message,
            line: line,
            suggestion: suggestion,
            file: file,
          }.compact
        end
      end
    end
  end
end
