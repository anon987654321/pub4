# frozen_string_literal: true

module Master
  module CLI
    # Destructive slash commands and configurable blocking review (security.yml).
    module DestructiveRoutes
      SECURITY_PATH = Master.data_path("security.yml").freeze
      PATTERNS_PATH = Master.data_path("patterns.yml").freeze
      FALLBACK = %w[clear rebuild resync shell rollback].freeze

      module_function

      def destructive_commands
        @destructive_commands ||= load_destructive_commands
      end

      def destructive_command?(name)
        destructive_commands.include?(name.to_s)
      end

      def destructive_route?(ctx)
        return true if destructive_command?(ctx.command.to_s)
        return true if ctx.last_tool_tier == :dangerous

        false
      end

      def blocking_review?
        return false if ENV["MASTER_BLOCKING_REVIEW"] == "0"

        defaults = Master.load_yaml(SECURITY_PATH) || {}
        defaults.dig("tools", "custom", "require_review_for_destructive") != false
      end

      def load_destructive_commands
        return FALLBACK unless File.exist?(PATTERNS_PATH)

        data = Master.load_yaml(PATTERNS_PATH) || {}
        list = Array(data.dig("infer", "destructive")).map(&:to_s)
        list.empty? ? FALLBACK : list
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "destructive_routes.load")
        FALLBACK
      end
    end
  end
end
