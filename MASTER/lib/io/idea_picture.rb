# frozen_string_literal: true

require "json"
require "rbconfig"
require_relative "exec"

module Master
  module Io
    # MASTER-facing adapter for STUDIO photograph generation. MASTER owns the
    # request and the result contract; STUDIO owns provider calls, grading and
    # media creation.
    class IdeaPicture
      SCRIPT = File.expand_path("../../../STUDIO/photograph.rb", __dir__)

      def initialize(script: SCRIPT)
        @script = script
      end

      def write(words, film: true, duration: 5, timeout: Master::Io::Exec::DEFAULT_TIMEOUT)
        raise "STUDIO photograph entrypoint is unavailable" unless File.file?(@script)

        argv = [RbConfig.ruby, @script]
        argv << "--film" if film
        argv << "--duration" << duration.to_i.to_s
        argv << words.to_s
        stdout, status = Master::Io::Exec.capture2e(
          *argv, chdir: File.dirname(@script), timeout:, raise_on_timeout: true
        )
        raise "STUDIO photograph failed: #{stdout.lines.last.to_s.strip}" unless status.success?

        JSON.parse(stdout).transform_keys(&:to_sym)
      rescue Master::Io::Exec::TimeoutError => e
        raise "STUDIO photograph timed out: #{e.message}"
      end
    end
  end
end
