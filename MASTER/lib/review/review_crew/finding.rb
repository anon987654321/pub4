# frozen_string_literal: true

module Master
  module Review
    class ReviewCrew
      Finding = Struct.new(:agent, :severity, :category, :message, :line, :suggestion, :file, keyword_init: true) do
        def to_h
          {
            agent:,
            severity:,
            category:,
            message:,
            line:,
            suggestion:,
            file:,
          }.compact
        end
      end
    end
  end
end
