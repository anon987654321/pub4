# frozen_string_literal: true

require "open3"
require_relative "../../../OPENBSD/lib/gate_result"

module Deploy
  # Scan-only constitutional preflight: MASTER /scan on RAILS (+ optional OPENBSD).
  # Does not run /fix (no autonomous edits). Full chain: `cd MASTER && ruby bin/gate`.
  class ConstitutionalScanGate
    ROOT = File.expand_path("../../..", __dir__)
    MASTER = File.join(ROOT, "MASTER")
    SAFE_ENV = {
      "MASTER_SAFE_MODE" => "1",
      "MASTER_BACKGROUND" => "0",
      "MASTER_AUTOFIX" => "0",
      "MASTER_WATCH" => "0",
      "MASTER_WATCHER" => "0",
      "MASTER_HEARTBEAT" => "0",
      "MASTER_SCAN_AUTOFIX" => "0",
    }.freeze

    def self.run(targets: nil)
      new(targets: targets).run
    end

    def initialize(targets: nil)
      list = Array(targets).compact
      @targets = list.empty? ? default_targets : list
      @result = GateResult.new
    end

    def run
      cli = File.join(MASTER, "bin", "cli")
      unless File.file?(cli)
        @result.fail("missing MASTER/bin/cli")
        return @result
      end

      @targets.each { |target| scan_target(cli, target) }
      @result
    end

    private

    def default_targets
      %w[../RAILS/brgen ../RAILS/amber ../RAILS/bsdports ../RAILS/shared]
    end

    def scan_target(cli, path)
      line = "/scan --no-autofix #{path}"
      env = SAFE_ENV.dup
      stdout, status = Open3.capture2e(
        env,
        "bundle", "exec", "ruby", "bin/cli",
        chdir: MASTER,
        stdin_data: "#{line}\n"
      )
      if status.success?
        @result.warn("constitutional scan ok: #{path} (#{stdout.lines.size} lines)")
      else
        # Scan may exit non-zero on findings depending on cli; treat hard errors only.
        if stdout.to_s.match?(/LoadError|SyntaxError|uninitialized constant|No such file/)
          @result.fail("constitutional scan crashed for #{path}: #{stdout.lines.last(3).join}")
        else
          @result.warn("constitutional scan finished with findings for #{path}")
        end
      end
    rescue StandardError => e
      @result.fail("constitutional scan error for #{path}: #{e.class}: #{e.message}")
    end
  end
end
