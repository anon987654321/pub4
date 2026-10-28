# frozen_string_literal: true

require_relative "exec"

module Master
  module Io
    # Read-only local security observations; never installs, updates or escalates.
    class VulCheck
      NAME = "vul_check".freeze
      TIER = :guarded
      DESCRIPTION = "Read-only local security posture inventory.".freeze
      PROBE_TIMEOUT = 8
      SCANNER_TIMEOUT = 240
      SCANNERS = {
        "chkrootkit" => ["chkrootkit"],
        "rkhunter" => ["rkhunter", "--check", "--sk"],
        "aide" => ["aide", "--check"],
      }.freeze
      ANDROID_INDICATORS = [
        "/system/xbin/su", "/system/bin/su", "/sbin/su",
        "/system/app/Superuser.apk", "/data/adb/magisk"
      ].freeze

      def initialize(governor:, event_bus: nil)
        @governor = governor
        @bus = event_bus
      end

      def call(run_scanners: false)
        return Result.err("vul_check: run_scanners must be boolean", category: :validation) unless [true, false].include?(run_scanners)

        permit = @governor.permit?(NAME, TIER, "read-only local security inventory")
        return permit if permit.err?

        kind = platform
        return Result.err("vul_check: unsupported platform #{RUBY_PLATFORM}", category: :validation) if kind == :unsupported

        lines = [
          "MASTER local security posture",
          "Platform: #{kind} (#{RUBY_PLATFORM})",
          "Mode: #{run_scanners ? 'installed scanners requested' : 'read-only inventory'}",
          "Observations are evidence, not proof of compromise or proof of a clean system.",
          "",
        ]
        posture_probes(kind).each { |label, argv| lines << probe_line(label, argv) }
        lines.concat(android_indicators) if kind == :android

        if run_scanners
          scanner_permit = @governor.permit?(NAME, :dangerous, "run already-installed local security scanners; no installs or updates")
          return scanner_permit if scanner_permit.err?

          lines << ""
          lines << "Optional installed scanners"
          SCANNERS.each do |name, argv|
            executable = Exec.which(name)
            lines << (executable ? scanner_line(name, [executable, *argv.drop(1)]) : "#{name}: UNAVAILABLE (not installed)")
          end
        else
          lines << ""
          lines << "Optional scanners: NOT RUN. Set run_scanners=true to request a second dangerous-tier approval."
        end
        @bus&.publish("tool:after", tool: NAME, platform: kind, scanners: run_scanners)
        Result.ok(lines.join("\n").byteslice(0, 12_000))
      rescue StandardError => e
        Result.err("vul_check: #{e.class}: #{e.message}", category: :infrastructure)
      end

      private

      def platform
        value = RUBY_PLATFORM.downcase
        return :android if value.include?("android")
        return :macos if value.include?("darwin")
        return :openbsd if value.include?("openbsd")
        return :linux if value.include?("linux")
        :unsupported
      end

      def posture_probes(kind)
        common = [["Effective identity", ["id"]], ["Kernel and host", ["uname", "-a"]]]
        specific = case kind
                   when :macos
                     [
                       ["System version", ["sw_vers"]],
                       ["System Integrity Protection", ["/usr/bin/csrutil", "status"]],
                       ["Gatekeeper", ["/usr/sbin/spctl", "--status"]],
                       ["FileVault status", ["/usr/bin/fdesetup", "status"]],
                       ["Packet filter status", ["/sbin/pfctl", "-s", "info"]],
                     ]
                   when :openbsd
                     [["Secure level", ["sysctl", "kern.securelevel"]],
                      ["Packet filter status", ["pfctl", "-s", "info"]],
                      ["Patch check availability", ["syspatch", "-c"]]]
                   when :android
                     [["Android release", ["getprop", "ro.build.version.release"]],
                      ["Security patch level", ["getprop", "ro.build.version.security_patch"]],
                      ["Verified boot state", ["getprop", "ro.boot.verifiedbootstate"]],
                      ["Debuggable build flag", ["getprop", "ro.debuggable"]]]
                   else
                     [["ASLR setting", ["sysctl", "kernel.randomize_va_space"]],
                      ["Kernel pointer restriction", ["sysctl", "kernel.kptr_restrict"]],
                      ["Kernel message restriction", ["sysctl", "kernel.dmesg_restrict"]]]
                   end
        common + specific
      end

      def probe_line(label, argv)
        executable = argv.first.to_s
        path = executable.start_with?("/") ? executable : Exec.which(executable)
        return "#{label}: UNAVAILABLE (#{executable} not found)" unless path

        out, err, status = Exec.capture3(path, *argv.drop(1), timeout: PROBE_TIMEOUT)
        state = status.success? ? "OBSERVED" : "INCONCLUSIVE (exit #{status.exitstatus || status.termsig})"
        detail = [out.to_s.strip, err.to_s.strip].reject(&:empty?).join(" | ")
        "#{label}: #{state}#{detail.empty? ? '' : " — #{detail.byteslice(0, 900)}"}"
      rescue StandardError => e
        "#{label}: INCONCLUSIVE (#{e.class}: #{e.message})"
      end

      def android_indicators
        present = ANDROID_INDICATORS.select { |path| File.exist?(path) || File.symlink?(path) }
        su = Exec.which("su")
        [
          "Android root indicators (heuristics only):",
          present.empty? ? "  No listed path indicators observed." : "  REVIEW: #{present.join(', ')}",
          su ? "  REVIEW: su executable found at #{su}; presence alone is not proof of root access." : "  No su executable found on PATH.",
        ]
      end

      def scanner_line(name, argv)
        out, err, status = Exec.capture3(*argv, timeout: SCANNER_TIMEOUT)
        state = status.success? ? "COMPLETED" : "INCONCLUSIVE (exit #{status.exitstatus || status.termsig})"
        detail = [out.to_s.strip, err.to_s.strip].reject(&:empty?).join("\n")
        "#{name}: #{state}\n#{detail.byteslice(0, 8_000).to_s}"
      rescue StandardError => e
        "#{name}: INCONCLUSIVE (#{e.class}: #{e.message})"
      end
    end
  end
end
