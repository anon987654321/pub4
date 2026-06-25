# frozen_string_literal: true

module Master
  module Plugins
    module Reach
      TOOL_MAP = {
        "ReadFile"        => ->(r, i) {
          Master::Reach::ReadFile.new(root: r, undo: i[:undo], event_bus: i[:bus], ground_truth: i[:ground_truth])
        },
        "WriteFile"       => ->(r, i) {
          Master::Reach::WriteFile.new(root: r, undo: i[:undo], governor: i[:governor],
            event_bus: i[:bus], diff_stager: i[:diff_stager])
        },
        "StrReplace"      => ->(r, i) {
          Master::Reach::StrReplace.new(root: r, undo: i[:undo], governor: i[:governor],
            event_bus: i[:bus], diff_stager: i[:diff_stager])
        },
        "BatchReplace"    => ->(r, i) {
          Master::Reach::BatchReplace.new(root: r, governor: i[:governor], event_bus: i[:bus])
        },
        "AstEdit"         => ->(r, i) { Master::Reach::AstEdit.new(root: r, undo: i[:undo], event_bus: i[:bus]) },
        "Tree"            => ->(r, i) { Master::Reach::Tree.new(root: r, event_bus: i[:bus]) },
        "ListDir"         => ->(r, i) { Master::Reach::ListDir.new(root: r, event_bus: i[:bus]) },
        "SearchFiles"     => ->(r, i) { Master::Reach::SearchFiles.new(root: r, event_bus: i[:bus]) },
        "SearchKnowledge" => ->(r, i) { Master::Reach::SearchKnowledge.new(root: r, event_bus: i[:bus]) },
        "SymbolLookup"    => ->(r, i) {
          Master::Reach::SymbolLookup.new(code_index: i[:code_index], event_bus: i[:bus])
        },
        "Shell"           => ->(r, i) {
          Master::Reach::Shell.new(root: r, governor: i[:governor], event_bus: i[:bus], library_verify: i[:library_verify])
        },
        "GitContext"      => ->(r, i) { Master::Reach::GitContext.new(root: r, event_bus: i[:bus]) },
        "WebFetch"        => ->(r, i) { Master::Reach::WebFetch.new(governor: i[:governor], event_bus: i[:bus]) },
        "WebSearch"       => ->(r, i) { Master::Reach::WebSearch.new(governor: i[:governor], event_bus: i[:bus]) },
        "Clean"           => ->(r, i) { Master::Reach::Clean.new(root: r, governor: i[:governor], event_bus: i[:bus]) },
        "FeedbackRecord"  => ->(r, i) { Master::Reach::FeedbackRecord.new(learnings: i[:learnings]) },
        "Repligen"        => ->(r, i) { Master::Reach::Repligen.new(root: r, event_bus: i[:bus]) },
        "Postpro"         => ->(r, i) { Master::Reach::Postpro.new(root: r, event_bus: i[:bus]) },
      }.freeze

      def self.boot(root:, config:, bus:)
        breaker = Master::Reach::CircuitBreakerRegistry.new(
          budget_max: config.budget_max, req_max: config.req_max, event_bus: bus
        )
        cache = Master::Reach::SemanticCache.new(root:, ttl: config["cache_ttl"], event_bus: bus)
        mcp   = Master::Reach::McpCoordinator.new(root:, event_bus: bus)
        provider_health = Master::Now::Routing::ProviderHealth.new(
          path: File.join(root, "runtime", "telemetry", "provider_health.ndjson")
        )
        mcp.connect_all
        { breaker:, cache:, mcp:, provider_health: }
      end

      def self.build_tools(root:, infra:)
        path = File.join(root, "data", "tools.yml")
        defs = Master.load_yaml(path)
        return [] unless defs.is_a?(Array)
        tools = defs.filter_map do |defn|
          next unless defn["default"] == true
          factory = TOOL_MAP[defn["name"].to_s]
          factory ? factory.call(root, infra) : (infra[:bus]&.publish("builder:tool_skipped", tool: defn["name"]); nil)
        end
        tools
      end

      Master::Plugin.register(:reach, self)
    end
  end
end
