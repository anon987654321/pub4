# frozen_string_literal: true

module Master
  module CLI
    module RuntimeMode
      PIPELINE_STAGES = "Intake → Enhance → Infer → Route → Guard → Deliberate → Execute → Review → Memory → Render".freeze

      module_function

      def summary(config: nil)
        safe = ENV.fetch("MASTER_SAFE_MODE", "1") == "1" ? "safe" : "active"
        visitor = visitor_tier?(config) ? "visitor" : "full"
        web = ENV.fetch("MASTER_WEB", "0") == "1" ? "web" : "cli"
        loops = loop_line
        "#{safe} · #{visitor} · #{web} · #{loops}"
      end

      def visitor_tier?(config)
        token = config&.dig("web_token").to_s
        token.empty?
      end

      def loop_line
        slot = Ops::LoopSlot.status
        autofix = ENV["MASTER_AUTOFIX"] == "1" ? "autofix" : "no-autofix"
        owner = slot[:owner].to_s.empty? ? "none" : slot[:owner]
        "#{autofix} loop=#{slot.fetch(:selected, "none")} owner=#{owner}"
      rescue StandardError
        autofix = ENV["MASTER_AUTOFIX"] == "1" ? "autofix" : "no-autofix"
        "#{autofix} loop=none"
      end
    end
  end
end
