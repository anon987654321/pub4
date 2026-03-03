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
    require_relative "chamber/review" unless const_defined?(:Review, false)
    require_relative "chamber/deliberation" unless const_defined?(:Deliberation, false)
    require_relative "chamber/ideation" unless const_defined?(:Ideation, false)

    include ::MASTER::Council::Review
    include ::MASTER::Council::Deliberation
    include ::MASTER::Council::Ideation

    MAX_ROUNDS = 25
    MAX_COST = 0.50
    CONSENSUS_THRESHOLD = 0.70
    CONVERGENCE_THRESHOLD = 0.05

    MODELS = {
      sonnet: "anthropic/claude-sonnet-4.6",
      grok: "x-ai/grok-code-fast-1",
      deepseek: "deepseek/deepseek-chat",
      kimi: "moonshotai/kimi-k2.5",
      glm: "z-ai/glm-5",
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
      tiers = LLM.load_models_config.group_by { |m| m[:tier]&.to_sym }
      tiers[:strong]&.first&.dig(:id) || "anthropic/claude-sonnet-4.6"
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

  Chamber = Council
end
