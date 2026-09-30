# frozen_string_literal: true

require_relative "../voice/aesthetic"

module Master
  module CLI
    module BootBanner
      module_function

      def print(io: $stderr)
        return unless ENV["MASTER_BOOT_STATUS"] == "1"

        banner_lines.each { |line| io.puts(line) }
      end

      def banner_lines
        status = Master::Ops::LoopSlot.status
        budget = Master::Ops::ProcessBudget.status
        brutalist = ENV["MASTER_BRUTALIST"] == "1"
        aesthetic = Master::Voice::Aesthetic.mode
        lines = [
          "boot0 at mainbus0: safe #{ENV.fetch("MASTER_SAFE_MODE", "1")}, web #{ENV.fetch("MASTER_WEB", "0")}",
          "loop0 at master0: #{status.fetch(:selected, "none")}, owner #{status.fetch(:owner, "none")}",
          "budget0 at master0: valid #{budget[:valid]}, slot #{budget.fetch(:slot, "unknown")}",
          "style0 at master0: #{aesthetic}",
          "motd0 at master0: #{motd_spotlight}",
          "master0: ready",
        ]
        if brutalist || aesthetic == "wscons"
          profile = aesthetic == "wscons" ? "wscons" : "brutalist"
          lines << "style0 at master0: profile #{profile}, motion steps, typography mono"
          lines << "style0: entropy and confidence inspectable"
        end
        lines
      end

      def motd_spotlight
        path = File.join(Master::DATA, "patterns.yml")
        return "scan+face+council" unless File.exist?(path)

        spots = Array(Master.load_yaml(path).dig("motd", "spots"))
        return "scan+face+council" if spots.empty?

        index = Time.now.to_i / 86_400 % spots.size
        format_motd_spot(spots[index])
      rescue StandardError
        "scan+face+council"
      end

      def format_motd_spot(spot)
        spot.to_s.gsub("%{rule_count}", Master.rule_count(root: Master::ROOT).to_s)
      end
    end
  end
end
