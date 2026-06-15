# frozen_string_literal: true

module Master
  module Now
    module BootBanner
      module_function

      def print(io: $stderr)
        return unless ENV["MASTER_BOOT_STATUS"] == "1"

        status = Master::Ops::LoopSlot.status
        budget = Master::Ops::ProcessBudget.status
        io.puts "process: safe=#{ENV.fetch("MASTER_SAFE_MODE", "1")} background=#{ENV.fetch("MASTER_BACKGROUND", "0")} web=#{ENV.fetch("MASTER_WEB", "0")} loop=#{status[:selected] || "none"} valid=#{budget[:valid]}"
      end
    end
  end
end
