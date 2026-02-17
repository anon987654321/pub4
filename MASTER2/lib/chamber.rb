# frozen_string_literal: true

require_relative "chamber/creative"
require_relative "chamber/swarm"
require_relative "chamber/review"
require_relative "chamber/deliberation"
require_relative "chamber/ideation"

module MASTER
  # Council - Multi-model deliberation with council personas
  # Implements multi-round debate: Independent -> Synthesis -> Convergence
  class Council
    include Review
    include Deliberation
    include Ideation
    MAX_ROUNDS = 25
    MAX_COST = 0.50
    CONSENSUS_THRESHOLD = 0.70
    CONVERGENCE_THRESHOLD = 0.05

    MODELS = {
      sonnet: nil,    # Will be resolved via LLM.select_model
      deepseek: nil,  # Will be resolved via LLM.select_model
      gemini: nil,    # Will be resolved via LLM.select_model
    }.freeze

    ARBITER = :sonnet

    attr_reader :cost, :rounds, :proposals

    def initialize(llm: LLM)
      @llm = llm
      @cost = 0.0
      @rounds = 0
      @proposals = []
    end

    def arbiter_model
      LLM.model_tiers[:strong]&.first || "anthropic/claude-sonnet-4"
    end

    # Convenience method for single council review
    # @param text [String] Code or text to review
    # @param model [String, nil] Optional model override
    # @return [Hash] Review result with votes and consensus
    class << self
      def council_review(text, model: nil)
        chamber = new(llm: LLM)
        chamber.council_review(text, text, model: model)
      end
    end

    private

    def over_budget?
      @cost >= MAX_COST
    end
  end

  Chamber = Council # deprecated: use Council
end
