# frozen_string_literal: true

module Master
  module Now
    module BootBanner
      module_function

      def print(io: $stderr)
        return unless ENV["MASTER_BOOT_STATUS"] == "1"

        banner_lines.each { |line| io.puts(line) }
      end

      def banner_lines
        status = Master::Ops::LoopSlot.status
        budget = Master::Ops::ProcessBudget.status
        [
          "master: boot safe=#{ENV.fetch("MASTER_SAFE_MODE", "1")} web=#{ENV.fetch("MASTER_WEB", "0")}",
          "master: background=#{ENV.fetch("MASTER_BACKGROUND", "0")} watch=#{ENV.fetch("MASTER_WATCH", "0")}",
          "master: loop=#{status[:selected] || "none"} owner=#{status[:owner] || "none"}",
          "master: budget valid=#{budget[:valid]} slot=#{budget[:slot] || "unknown"}",
          "master: motd #{motd_spotlight}",
          "master: ready dmesg=preserved",
        ]
      end

      def motd_spotlight
        path = File.join(Master::DATA, "motd.yml")
        return "scan+face+council" unless File.exist?(path)

        spots = Array(Master.load_yaml(path).fetch("spots", []))
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
