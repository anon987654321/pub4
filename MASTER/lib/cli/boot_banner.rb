# frozen_string_literal: true

require_relative "../ground/pledge"
require_relative "../core"
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

      def banner_lines = [*attach_lines, "master0: ready"]

      # The banner's units without its closing line, for the splash, where
      # "root on master0" is what says the boot is done.
      def attach_lines
        status = Master::Ops::LoopSlot.status
        budget = Master::Ops::ProcessBudget.status
        brutalist = ENV["MASTER_BRUTALIST"] == "1"
        aesthetic = Master::Voice::Aesthetic.mode
        profile = "wscons" if aesthetic == "wscons"
        profile ||= "brutalist" if brutalist
        style = "style0 at master0: #{aesthetic}"

        [
          "boot0 at mainbus0: safe #{ENV.fetch("MASTER_SAFE_MODE", "1")}, web #{ENV.fetch("MASTER_WEB", "0")}",
          *security_lines,
          loop_line(status),
          "budget0 at master0: valid #{budget[:valid]}, slot #{budget.fetch(:slot, "unknown")}",
          style,
          "motd0 at master0: #{motd_spotlight}",
        ].tap do |lines|
          if profile
            lines << "style0: profile #{profile}, motion steps, typography mono"
            lines << "style0: entropy and confidence inspectable"
          end
        end
      end

      def security_lines
        profile = Master::Core::Capabilities.for(:fix)
        [
          "security0 at master0: secure defaults, law-bound admission",
          "cap0 at security0: profile #{profile.name}, #{profile.capabilities.join(" ")}",
          pledge_line,
          "memory0 at security0: unveil-style restricted views available",
          "patch0 at security0: transaction-backed self-change with rollback",
          # authority0, not model0: the splash's model0 is the model itself, and
          # a unit name, as in the kernel, names one device.
          "authority0 at security0: proposal-only; effects need capability admission",
        ]
      end

      # Prose, as the kernel says it, and claimed only where pledge exists;
      # elsewhere the kernel's own phrase for a unit with nothing behind it.
      def pledge_line
        "pledge0 at security0: #{Master::Ground::Pledge.openbsd? ? "staged reduction" : "not configured"}"
      end

      # No loop selected is "none", not an empty field before the comma.
      def loop_line(status)
        selected = status[:selected].to_s
        "loop0 at master0: #{selected.empty? ? "none" : selected}, owner #{status.fetch(:owner, "none")}"
      end

      def motd_spotlight
        spots = Array(Master.patterns_config.dig("motd", "spots"))
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
