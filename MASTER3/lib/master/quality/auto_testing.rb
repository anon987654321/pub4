# frozen_string_literal: true

require "English"

module Master
  module Quality
    class AutoTesting
      CHECKS = {
        "rubocop" => "bundle exec rubocop --format simple",
        "brakeman" => "bundle exec brakeman -q",
        "reek" => "bundle exec reek"
      }.freeze

      def run
        results = CHECKS.map { |name, cmd| [name, run_cmd(cmd)] }.to_h
        coverage = run_cmd("bundle exec rspec --format progress")
        { checks: results, coverage_gate: coverage }
      end

      private

      def run_cmd(cmd)
        ok = system("/bin/sh", "-c", "command -v #{cmd.split[2] || cmd.split.first} >/dev/null 2>&1")
        return { status: :skipped, reason: "missing dependency", command: cmd } unless ok

        output = IO.popen(["/bin/sh", "-c", "#{cmd} 2>&1"], &:read)
        { status: $CHILD_STATUS.success? ? :pass : :fail, command: cmd, output: output.lines.first(20).join }
      rescue StandardError => e
        { status: :fail, command: cmd, output: e.message }
      end
    end
  end
end
