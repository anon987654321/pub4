# frozen_string_literal: true

require "timeout"
require_relative "../io/exec"

module Master
  module Mobile
    # Hands one utterance to bin/master as a child process and returns what it
    # printed. The child runs as MASTER_INTERNAL_CHILD, so it does not contend
    # for the control-plane lock the host already holds. Io::Exec bounds the
    # child and kills its process group on overrun; a bare Timeout around Open3
    # left the child running.
    class Bridge
      Result = Data.define(:ok, :output, :error) do
        def ok? = ok == true
      end

      CHILD_ENV = {
        "MASTER_PROFILE" => "mobile", "MASTER_INTERNAL_CHILD" => "1", "MASTER_BACKGROUND_SCAN" => "0",
        "MASTER_WEB" => "0", "MASTER_CLI_QUIET" => "1", "MASTER_SKIP_BOOT_SCAN" => "1"
      }.freeze

      def initialize(root:, timeout_s: 120, capture: nil)
        @root = File.expand_path(root)
        @timeout_s = Integer(timeout_s)
        @capture = capture || lambda do |*argv, **opts|
          Master::Io::Exec.capture3(*argv, timeout: @timeout_s, raise_on_timeout: true, **opts)
        end
      end

      def submit_utterance!(text)
        text = text.to_s.strip
        return failed("empty utterance") if text.empty?

        out, err, status = Timeout.timeout(@timeout_s) do
          @capture.call(CHILD_ENV, File.join(@root, "bin", "master"), "-m", text, chdir: @root)
        end
        return Result.new(ok: true, output: out.to_s, error: nil) if status.success?

        failed(err.to_s.strip.empty? ? "bin/master exited #{status.exitstatus}" : err.to_s.strip)
      rescue Timeout::Error, Master::Io::Exec::TimeoutError
        failed("no answer within #{@timeout_s}s")
      rescue SystemCallError => e
        failed("#{e.class}: #{e.message}")
      end

      private

      def failed(error) = Result.new(ok: false, output: nil, error:)
    end
  end
end
