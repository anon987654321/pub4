# frozen_string_literal: true

module MASTER
  class Pipeline
    # Context - Typed struct holding all pipeline stage data
    # Provides a single, structured object passed between stages
    Context = Struct.new(
      :text,              # [String] Input text after intake
      :model,             # [String] Selected model ID
      :tier,              # [Symbol] Model tier (:strong, :fast, :cheap, etc.)
      :council_verdict,   # [Symbol, nil] Council verdict (:approved, :vetoed, nil)
      :council_vetoed,    # [Boolean] Whether council vetoed
      :council_vetoes,    # [Array] Names of vetoing council members
      :council_votes,     # [Array] All council votes
      :response,          # [String, nil] LLM response content
      :tokens_in,         # [Integer] Input token count
      :tokens_out,        # [Integer] Output token count
      :cost,              # [Float] Request cost in USD
      :axiom_violations,  # [Array] List of axiom violation names
      :design_violations, # [Array] List of NNG design violations
      :linted,            # [Boolean] Whether lint stage ran
      :rendered,          # [String, nil] Typography-rendered response
      :executed,          # [Boolean, nil] Whether Execute stage ran
      :exec_results,      # [Array, nil] Results from code execution
      :bytes_compressed,  # [Integer, nil] Bytes removed by compression
      :streamed,          # [Boolean] Whether response was streamed
      :pattern,           # [Symbol] Execution pattern used
      :steps,             # [Integer] Number of executor steps taken
      :history,           # [Array] Executor step history
      keyword_init: true,
    ) do
      # Build a Context from a plain hash (symbolized keys)
      # @param hash [Hash] Source hash
      # @return [Context] New context instance
      def self.from_hash(hash)
        known_keys = members
        filtered = hash.transform_keys(&:to_sym).slice(*known_keys)
        new(**filtered)
      end

      # Merge additional values into context, returning new instance
      # @param updates [Hash] Key-value pairs to merge
      # @return [Context] New context with updates applied
      def merge(updates)
        h = to_h.merge(updates.transform_keys(&:to_sym))
        self.class.from_hash(h)
      end

      # Convert to plain hash, dropping nil values
      # @return [Hash] Compact hash representation
      def to_compact_h
        to_h.compact
      end
    end
  end
end
