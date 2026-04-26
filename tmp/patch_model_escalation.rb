# Phase 6: Dynamic model escalation
# Part A: model_router.rb — add ESCALATION_CHAIN, tier_for_model, next_escalation_tier, confidence_threshold

router_path = "/home/dev/pub4/MASTER/lib/master/routing/model_router.rb"
src = File.read(router_path)

# Add ESCALATION_CHAIN after UNCERTAINTY_PHRASES
src.sub!(
  "      ].freeze",
  <<~'RUBY'.chomp
      ].freeze

      ESCALATION_CHAIN = %w[cheap default strong].freeze
  RUBY
)

# Add tier_for_model, next_escalation_tier, confidence_threshold as public methods before private
old_private = "      private\n\n      def enabled?"
new_methods = <<~'RUBY'.chomp
      # Determine which tier a model belongs to.
      def tier_for_model(model_id)
        @rules.fetch("models", {}).each do |tier, models|
          return tier if models.is_a?(Array) && models.any? { |m| m["id"] == model_id }
        end
        "cheap"
      end

      # Return the next tier in the escalation chain, or nil if already at top.
      def next_escalation_tier(current_tier)
        idx = ESCALATION_CHAIN.index(current_tier.to_s)
        return nil unless idx
        ESCALATION_CHAIN[idx + 1]
      end

      # Per-task confidence threshold from routes config.
      # Falls back to 0.3 (the existing default).
      def confidence_threshold(task_type: :exploration)
        route = @rules.dig("routes", task_type.to_s)
        return 0.3 unless route.is_a?(Hash)
        route.fetch("confidence_threshold", 0.3).to_f
      end

      private

      def enabled?
RUBY

src.sub!(old_private, new_methods)

File.write(router_path, src)
puts "model_router.rb patched"
puts `ruby -c #{router_path} 2>&1`

# Part B: agent.rb — replace escalation_attempted boolean with escalation_depth counter
agent_path = "/home/dev/pub4/MASTER/lib/master/agent.rb"
agent_src = File.read(agent_path)

# Fix chat method signature: escalation_attempted → escalation_depth
agent_src.gsub!("escalation_attempted: false", "escalation_depth: 0")
agent_src.gsub!("escalation_attempted: true", "escalation_depth: escalation_depth + 1")

# Fix maybe_escalate call
agent_src.sub!(
  "last_response = maybe_escalate(last_response, prompt, context, message, stream, escalation_attempted, &blk)",
  "last_response = maybe_escalate(last_response, prompt, context, message, stream, escalation_depth, &blk)"
)

# Fix maybe_escalate method
agent_src.sub!(
  "    def maybe_escalate(last_response, prompt, context, original_message, stream, escalation_attempted, &blk)\n      return last_response unless @model_router\n      return last_response if escalation_attempted",
  "    # Escalates up to 2 times per chat call (depth counter replaces boolean).\n    def maybe_escalate(last_response, prompt, context, original_message, stream, escalation_depth, &blk)\n      return last_response unless @model_router\n      return last_response if escalation_depth >= 2"
)

File.write(agent_path, agent_src)
puts "agent.rb patched"
puts `ruby -c #{agent_path} 2>&1`
