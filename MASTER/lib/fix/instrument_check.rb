# frozen_string_literal: true

require "fileutils"
require "rbconfig"
require "tmpdir"
require_relative "../io/exec"
require_relative "resource_budget"
require_relative "../execution/contract"

module Master
  module Fix

    # What /fix depends on to measure anything, tried once before the first file. A run whose disk probe,
    # patch tool or linter is broken does not fail; it reports thousands of files as scanned and clean, or
    # each as a "scan error", and the numbers look like a result. Today's check refused every stage on a
    # NameError a rescue had swallowed. This names the broken instrument instead, and stops.
    #
    # Each probe returns nil when the instrument works and a one-line reason when it does not.
    # MASTER_FIX_INSTRUMENT_CHECK=0 skips the check for a run that knowingly lacks one.
    class InstrumentCheck
      class Unavailable < StandardError; end

      PROBES = %i[disk git patch_tool ruby_child cache_dir linter].freeze

      def initialize(root:, bus: nil, probes: PROBES)
        @root = File.expand_path(root)
        @bus = bus
        @probes = probes
      end

      def failures
        @probes.filter_map do |name|
          reason = send(:"probe_#{name}")
          "#{name}: #{reason}" if reason
        rescue StandardError => e
          "#{name}: probe raised #{e.class}: #{e.message}"
        end
      end

      # The failures to report: none when the check is switched off.
      def broken(env: ENV) = env["MASTER_FIX_INSTRUMENT_CHECK"] == "0" ? [] : failures

      # Adapt the live preflight to the shared verifier vocabulary. A disabled
      # preflight is NOT a pass; it is explicitly not applicable with unchecked
      # probes recorded. Failure messages remain local to the caller.
      def verification_result(env: ENV)
        if env["MASTER_FIX_INSTRUMENT_CHECK"] == "0"
          @last_failures = []
          return Master::Execution::Contract::VerificationResult.new(
            id: "fix-instruments", subject: "fix-instruments",
            verifier: "fix-instrument-check", status: :not_applicable,
            scope: @root, checked_count: 0, failure_count: 0,
            unchecked_count: @probes.length, complete: true
          )
        end

        @last_failures = failures
        Master::Execution::Contract::VerificationResult.new(
          id: "fix-instruments", subject: "fix-instruments",
          verifier: "fix-instrument-check",
          status: @last_failures.empty? ? :pass : :blocked,
          scope: @root, checked_count: @probes.length,
          failure_count: @last_failures.length, unchecked_count: 0, complete: true
        )
      end

      def verify!
        verification = verification_result
        return true if %i[pass not_applicable].include?(verification.status)

        broken = Array(@last_failures)
        @bus&.publish(
          "fix_loop:instruments_unavailable",
          verification: verification.to_h,
          failure_count: broken.size,
          failure_digest: Digest::SHA256.hexdigest(broken.join("\n")),
        )
        raise Unavailable, "fix instruments unavailable: #{broken.join("; ")}"
      end

      private

      def probe_disk
        gb = Master::Fix::ResourceBudget.new(root: @root).disk_free_gb_for(@root)
        gb.nil? ? "free space could not be read" : nil
      end

      def probe_git
        _out, status = Master::Io::Exec.capture2e("git", "-C", @root, "rev-parse", "--git-dir")
        status.success? ? nil : "#{@root} is not inside a git work tree"
      end

      def probe_patch_tool
        dirs = ENV.fetch("PATH", "").split(File::PATH_SEPARATOR)
        found = dirs.any? { |dir| File.executable?(File.join(dir, "patch")) }

        found ? nil : "patch(1) is not on PATH, so no model diff can be applied"
      end

      # A child ruby is how every check and test runs; it must be the ruby running this process.
      def probe_ruby_child
        out, status = Master::Io::Exec.capture2e(RbConfig.ruby, "-e", "print RUBY_VERSION")
        return "#{RbConfig.ruby} did not start" unless status.success?

        out.strip == RUBY_VERSION ? nil : "child ruby is #{out.strip}, this process is #{RUBY_VERSION}"
      end

      def probe_cache_dir
        dir = File.join(@root, ".master", "lint_cache")
        FileUtils.mkdir_p(dir)
        probe = File.join(dir, ".write_probe#{Process.pid}")

        File.write(probe, "ok")
        File.delete(probe)
        nil
      rescue SystemCallError => e
        "#{dir} is not writable (#{e.class})"
      end

      # Only when the external linters are on: a clean file must come back with no scan error.
      def probe_linter
        return if ENV["MASTER_EXTERNAL_LINT"] == "0"

        require_relative "../../law/detectors/external_linter_laws"
        rule = Master::Review::Scan::Laws::RubocopLaw.new(root: @root)
        return unless rule.linter_available?("rubocop")

        Dir.mktmpdir("instrument-check") do |dir|
          path = File.join(dir, "probe.rb")

          File.write(path, "# frozen_string_literal: true\n\nx = 1\n")
          error = rule.check("", path:).find { |finding| finding.message.include?("scan error") }
          error&.message
        end
      end
    end
  end
end
