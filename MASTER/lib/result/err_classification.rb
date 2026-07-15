# frozen_string_literal: true

module Master
  class Result
    # Retry-policy classification for Result::Err — separate from Err's own
    # value-identity and monad-chaining methods.
    module ErrClassification
      RETRIABLE = %i[infrastructure timeout].freeze
      PERMANENT = %i[validation axiom_violation budget].freeze

      def retriable? = RETRIABLE.include?(@category)
      def permanent? = PERMANENT.include?(@category)
    end
  end
end
