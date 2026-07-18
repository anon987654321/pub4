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
          "master: boot safe=#{ENV.fetch("MASTER_SAFE_MODE", "1")} web=#{ENV.fetch("MASTER_WEB", "0")}",
          "master: background=#{ENV.fetch("MASTER_BACKGROUND", "0")} watch=#{ENV.fetch("MASTER_WATCH", "0")}",
          "master: loop=#{status.fetch(:selected, "none")} owner=#{status.fetch(:owner, "none")}",
          "master: budget valid=#{budget[:valid]} slot=#{budget.fetch(:slot, "unknown")}",
          "master: aesthetic=#{aesthetic}",
          "master: motd #{motd_spotlight}",
          "master: ready dmesg=preserved",
        ]
        if brutalist || aesthetic == "wscons"
          profile = aesthetic == "wscons" ? "wscons" : "brutalist"
          lines << "master: profile=#{profile} motion=steps typography=mono"
          lines << "master: H=entropy C=confidence mode=inspectable"
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
