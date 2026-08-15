# frozen_string_literal: true

module Master
  class Result
    # Retry-policy classification for Result::Err — separate from Err's own
    # value-identity and monad-chaining methods.
    #
    # Result::CATEGORIES declares fourteen. This classified five, so nine —
    # including rate_limit and every provider failure — answered false to both
    # questions. A caller asking `retriable?` about a rate limit would have been
    # told no and given up on the one failure that is retriable by definition.
    #
    # Nothing asks yet: neither predicate has a caller anywhere in lib/, which is
    # why the gap was invisible and why closing it changes no behaviour. It is
    # closed now rather than when something finally reads it, because the shape
    # of that bug is a retry loop that quietly does not retry.
    #
    # The partition is total and disjoint, and test_err_classification.rb holds
    # it to both — a category added to CATEGORIES and to neither list here is the
    # same defect returning.
    module ErrClassification
      # Worth trying again as-is, or after a wait: the failure is in the
      # environment rather than in what was asked.
      RETRIABLE = %i[infrastructure timeout provider_error llm_failure llm_call_failure rate_limit].freeze

      # Retrying reproduces it. Either the request is wrong, the answer is no, or
      # the operation is over.
      PERMANENT = %i[validation axiom_violation budget no_api_key policy shutdown abort handler_exception].freeze

      def retriable? = RETRIABLE.include?(@category)
      def permanent? = PERMANENT.include?(@category)

      # :unknown is the one category that is neither, and deliberately: it is
      # what Result.err defaults to, so it means "nobody said", and answering
      # either question for it would be an invention. A caller that must decide
      # should treat it as permanent — the safe direction is not retrying.
      def classified? = retriable? || permanent?
    end
  end
end
