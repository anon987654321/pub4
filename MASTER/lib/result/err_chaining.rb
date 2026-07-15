# frozen_string_literal: true

module Master
  class Result
    # Functor/monad composition for Result::Err — all three are identity
    # no-ops (an Err short-circuits the chain) — kept separate from Err's own
    # value-identity and error-classification methods.
    module ErrChaining
      def map(&) = self
      def flat_map(&) = self
      def and_then(*) = self
    end
  end
end
