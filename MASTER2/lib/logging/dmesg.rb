# frozen_string_literal: true

require "open3"

module Logging
  module Dmesg
    DMESG_BINARY = "dmesg"
    DMESG_TIME_ARGS = "--ctime"
    DMESG_TAIL_ARGS = "--nopager"
    DEFAULT_DMESG_LINES = 200
    EMPTY_RESULT = "".freeze

    module_function

    def dmesg_log(logger: nil, lines: DEFAULT_DMESG_LINES)
      output = collect_dmesg(lines: lines)
      logger&.info(output) unless output.empty?
      output
    end

    def collect_dmesg(lines:)
      return EMPTY_RESULT unless dmesg_available?

      stdout, status = Open3.capture2e(*dmesg_command(lines))
      return EMPTY_RESULT unless status.success?

      stdout.to_s.strip
    rescue StandardError
      EMPTY_RESULT
    end

    def dmesg_available?
      system("command -v #{DMESG_BINARY} >/dev/null 2>&1")
    end

    def dmesg_command(lines)
      args = [DMESG_BINARY, DMESG_TIME_ARGS]
      args.concat([DMESG_TAIL_ARGS]) if supports_nopager?
      args.concat(["-T"]) if supports_timestamps? == false # keep compatibility (no-op if already ctime)
      args.concat(["-n", lines.to_i.to_s]) if supports_line_limit?
      args
    end

    def supports_nopager?
      @supports_nopager ||= help_text.include?(DMESG_TAIL_ARGS)
    end

    def supports_line_limit?
      @supports_line_limit ||= help_text.match?(/\B-n\b/)
    end

    def supports_timestamps?
      @supports_timestamps ||= help_text.match?(/\B-T\b/)
    end

    def help_text
      @help_text ||= begin
        stdout, _status = Open3.capture2e(DMESG_BINARY, "--help")
        stdout.to_s
      rescue StandardError
        EMPTY_RESULT
      end
    end
  end
end