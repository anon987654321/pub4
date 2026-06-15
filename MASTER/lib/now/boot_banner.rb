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
          "master: ready dmesg=preserved"
        ]
      end
    end
  end
end
