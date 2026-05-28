# frozen_string_literal: true

module Master
  module Now
  module Routing
    # Maps (intent, context) to a risk tier that governs model selection and
    # council requirements. Tiers: :low < :medium < :high < :critical.
    class RiskClassifier
      TIERS = %i[low medium high critical].freeze

      INTENT_TIERS = {
        critical: %i[destructive_command secret_handling permission_change public_deployment],
        high: %i[file_mutation auth_mutation security_audit production_runtime tool_execution],
        medium: %i[docs_change config_change preview_module api_design],
        low: %i[classification summarization cluster_label ui_copy explanation]
      }.freeze

      PATH_OVERRIDES = {
        /\bauth\b|\bsession\b|\bcredential\b|\bpassword\b|\btoken\b/i => :high,
        /\bsecret\b|\bapi[_\-]?key\b|\bprivate[_\-]?key\b/i => :critical,
        /\bpf\.conf\b|\bdoas\.conf\b|\bsshd\b|\bsmtpd\b/i => :critical,
        /\bbin\/cli\b|\blib\/ground\/axioms\b|\bdata\/standing_orders\b/i => :critical,
        /\blib\/loop\b|\blib\/judge\/security\b/i => :high,
        /\bapp\/controllers\b|\bapp\/models\b/i => :medium,
        /\btest\/\b|\bspec\/\b/i => :low
      }.freeze

      def self.call(intent: nil, touches: [])
        new.call(intent:, touches:)
      end

      def call(intent: nil, touches: [])
        path_tier = path_tier_for(Array(touches))
        intent_tier = intent_tier_for(intent)
        [path_tier, intent_tier].compact.max_by { |t| TIERS.index(t) } || :medium
      end

      private

      def intent_tier_for(intent)
        return nil if intent.nil?
        sym = intent.to_sym
        INTENT_TIERS.each { |tier, intents| return tier if intents.include?(sym) }
        nil
      end

      def path_tier_for(paths)
        return nil if paths.empty?
        paths.filter_map do |path|
          PATH_OVERRIDES.each do |re, tier|
            return tier if re.match?(path.to_s)
          end
          nil
        end.max_by { |t| TIERS.index(t) }
      end
    end
  end
  end
end
