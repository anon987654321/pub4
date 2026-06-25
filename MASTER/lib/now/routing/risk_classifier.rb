# frozen_string_literal: true

module Master
  module Now
    module Routing
      # Maps (intent, touches) to a risk tier governing model selection and
      # council requirements. Tiers: :low < :medium < :high < :critical.
      # Accepts an optional graph: (Master::Ground::EvidenceGraph) to elevate
      # tier based on cluster blast radius — files referenced by many clusters
      # carry higher blast radius and warrant stricter review.
      class RiskClassifier
        TIERS = %i[low medium high critical].freeze

        INTENT_TIERS = {
          critical: %i[destructive_command secret_handling permission_change public_deployment],
          high: %i[file_mutation auth_mutation security_audit production_runtime tool_execution],
          medium: %i[docs_change config_change preview_module api_design],
          low: %i[classification summarization cluster_label ui_copy explanation],
        }.freeze

        PATH_OVERRIDES = {
          /\bauth\b|\bsession\b|\bcredential\b|\bpassword\b|\btoken\b/i => :high,
          /\bsecret\b|\bapi[_\-]?key\b|\bprivate[_\-]?key\b/i => :critical,
          /\bpf\.conf\b|\bdoas\.conf\b|\bsshd\b|\bsmtpd\b/i => :critical,
          /\brelayd\.conf\b|\brc\.d\/|\/etc\/rc\.d\b/i => :critical,
          /\bdata\/(rules|soul|patterns|topologies)\.yml\b/i => :critical,
          /\bbin\/cli\b|\blib\/ground\/axioms\b|\bdata\/(?:state|standing_orders)\b/i => :critical,
          /\blib\/loop\b|\blib\/judge\/security\b/i => :high,
          /\bapp\/controllers\b|\bapp\/models\b/i => :medium,
          /\btest\/\b|\bspec\/\b/i => :low,
        }.freeze

        # Files referenced by this many clusters get tier elevation.
        BLAST_THRESHOLDS = [[5, :high], [3, :medium]].freeze

        def self.call(intent: nil, touches: [], graph: nil)
          new(graph:).call(intent:, touches:)
        end

        def initialize(graph: nil)
          @graph = graph
        end

        def call(intent: nil, touches: [])
          paths = Array(touches)
          tiers = [path_tier_for(paths), blast_tier_for(paths), intent_tier_for(intent)]
          tiers.compact.max_by { |t| TIERS.index(t) } || :medium
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
            PATH_OVERRIDES.each { |re, tier| return tier if re.match?(path.to_s) }
            nil
          end.max_by { |t| TIERS.index(t) }
        end

        def blast_tier_for(paths)
          return nil if @graph.nil? || paths.empty?
          paths.filter_map do |path|
            count = @graph.clusters_for_file(path.to_s).size
            BLAST_THRESHOLDS.find { |threshold, _| count >= threshold }&.last
          end.max_by { |t| TIERS.index(t) }
        rescue StandardError
          nil
        end
      end
    end
  end
end
