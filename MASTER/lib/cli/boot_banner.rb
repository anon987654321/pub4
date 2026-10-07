# frozen_string_literal: true

require_relative "../ground/pledge"
require_relative "../core/capabilities"
require_relative "../voice/aesthetic"
require_relative "../trace/dmesg"

module Master
  module CLI
    module BootBanner
      module_function

      def print(io: $stderr)
        return unless ENV["MASTER_BOOT_STATUS"] == "1"

        banner_lines.each do |line|
          Master::Trace::Dmesg::Report.print(
            line.split(":", 2).first.to_s,
            line,
            parent: "master0",
            io:,
          )
        end
      end

      def banner_lines
        status = Master::Ops::LoopSlot.status
        budget = Master::Ops::ProcessBudget.status
        brutalist = ENV["MASTER_BRUTALIST"] == "1"
        aesthetic = Master::Voice::Aesthetic.mode
        [
          "boot0 at mainbus0: safe #{ENV.fetch("MASTER_SAFE_MODE", "1")}, web #{ENV.fetch("MASTER_WEB", "0")}",
          *security_lines,
          "loop0 at master0: #{status.fetch(:selected, "none")}, owner #{status.fetch(:owner, "none")}",
          "budget0 at master0: valid #{budget[:valid]}, slot #{budget.fetch(:slot, "unknown")}",
          "style0 at master0: #{aesthetic}",
          "motd0 at master0: #{motd_spotlight}",
          "master0: ready",
        ].tap do |lines|
          if brutalist || aesthetic == "wscons"
            profile = aesthetic == "wscons" ? "wscons" : "brutalist"
            lines << "style0 at master0: profile #{profile}, motion steps, typography mono"
            lines << "style0: entropy and confidence inspectable"
          end
        end
      end

      def security_lines
        profile = Master::Core::Capabilities.for(:fix)
        [
          "security0 at master0: secure defaults, law-bound admission",
          "cap0 at security0: profile #{profile.name}, #{profile.capabilities.join(" ")}",
          "pledge0 at security0: openbsd=#{Master::Ground::Pledge.openbsd?}, staged reduction",
          "memory0 at security0: unveil-style restricted views available",
          "patch0 at security0: transaction-backed self-change with rollback",
          "model0 at security0: proposal-only; effects need capability admission",
        ]
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
