# frozen_string_literal: true



# ---- merged from lib/result/err_chaining.rb (one-file directory collapse, 2026-08-19) ----
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
# ---- merged from lib/result/err_classification.rb (one-file directory collapse, 2026-08-19) ----
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
# ---- merged from lib/result/ok_chaining.rb (one-file directory collapse, 2026-08-19) ----
module Master
  class Result
    # Functor/monad composition for Result::Ok (map/flat_map/and_then) — kept
    # separate from Ok's own value-identity methods (ok?/value!/unwrap/...).
    module OkChaining
      def map(&blk) = Result.ok(blk.call(@value))
      def flat_map(&blk) = blk.call(@value)

      def and_then(label = nil, &blk)
        result = blk.call(@value)
        result.is_a?(Result) ? result : Result.ok(result)
      rescue StandardError => e
        Result.err("#{label || "stage"}: #{e.message}", category: :infrastructure)
      end
    end
  end
end

module Master
  class Result
    CATEGORIES = {
      validation: "input failed preconditions",
      axiom_violation: "constitutional rule broken",
      provider_error: "upstream model / network failure",
      llm_failure: "LLM returned unusable output",
      llm_call_failure: "LLM dispatch exception (network / SDK)",
      no_api_key: "no LLM API key configured in env",
      infrastructure: "system / disk / git error",
      handler_exception: "unexpected error during handler execution",
      timeout: "operation exceeded deadline",
      rate_limit: "tier rate limit exceeded",
      budget: "cost limit hit",
      policy: "blocked by policy / kernel rule",
      shutdown: "user quit / shutdown requested",
      abort: "operation aborted",
    }.freeze

    def self.ok(value) = Ok.new(value)

    def self.from(value, err_msg:, category: :validation, context: nil)
      value.nil? ? err(err_msg, category:, context:) : ok(value)
    end

    def self.from_observation(observation)
      observation.ok? ? ok(observation.detail) : err(observation.message, category: :unknown)
    end

    def self.err(msg, category: :unknown, context: nil)
      raise ArgumentError, "unknown category: #{category}" unless category == :unknown || CATEGORIES.key?(category)

      Err.new(msg, category, error_context(msg, context, caller_locations(1, 1).first))
    end

    def self.error_context(msg, context, location)
      base = { file: location&.path, method: location&.base_label, attempted: msg.to_s }
      return base unless context
      context.respond_to?(:merge) ? base.merge(context) : base.merge(detail: context)
    end

    def self.wrap(val) = val.is_a?(Result) ? val : Ok.new(val)

    class Ok < Result
      include OkChaining

      attr_reader :value

      def initialize(value)
        @value = value
        freeze
      end

      def ok? = true
      def err? = false
      def value! = @value
      def unwrap = @value
      def value_or(_) = @value

      def deconstruct_keys(_keys) = { value: @value }
      def to_s = @value.to_s
      def inspect = "Ok(#{@value.inspect})"
    end

    class Err < Result
      include ErrChaining
      include ErrClassification

      attr_reader :message, :category, :context

      def initialize(message, category = :unknown, context = nil)
        raise ArgumentError, "message cannot be nil" if message.nil?
        raise ArgumentError, "category must be a symbol" unless category.is_a?(Symbol)

        @message = message
        @category = category
        @context = context
        freeze
      end

      def ok? = false
      def err? = true
      def value! = raise(Master::UnwrapError, "Err#value! called: #{@message}")
      def unwrap = value!
      def value_or(default) = default

      def deconstruct_keys(_keys) = { message: @message, category: @category, context: @context }
      def to_s = @message
      def inspect = @context ? "Err(#{@category}: #{@message} @ #{@context})" : "Err(#{@category}: #{@message})"
    end
  end
end
