# frozen_string_literal: true

module Master
  module Fix
    # The law a pass files its findings under when the pass owns one id and no
    # more: OpportunityPass, VisualPass and Wishlist each name themselves with it,
    # and the evidence and LLM stages read only #id and #severity.
    PassLaw = Data.define(:id) do
      def severity = :warning
    end
  end
end
