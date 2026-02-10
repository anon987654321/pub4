# frozen_string_literal: true

require "open3"
require "timeout"

module MASTER
  # Shell integration - zsh-native patterns
  module Shell
    extend self

    BUILTINS = %w[cd pwd echo print printf export alias source].freeze

    ZSH_PREFERRED = {
      'ls' => 'ls -F',
      'grep' => 'grep --color=auto',
      'cat' => 'cat -v',
      'rm' => 'rm -i',
      'mv' => 'mv -i',
      'cp' => 'cp -i'
    }.freeze

    FORBIDDEN = {
      'sudo' => 'doas',
      'apt' => 'pkg_add',
      'apt-get' => 'pkg_add',
      'yum' => 'pkg_add',
      'systemctl' => 'rcctl',
      'journalctl' => 'tail -f /var/log/messages'
    }.freeze

    class << self
      def sanitize(cmd)
        parts = cmd.strip.split(/\s+/)
        return cmd if parts.empty?

        base = parts.first

        # Replace forbidden commands
        if FORBIDDEN.key?(base)
          parts[0] = FORBIDDEN[base]
          return parts.join(' ')
        end

        # Apply zsh preferences
        if ZSH_PREFERRED.key?(base) && parts.size == 1
          return ZSH_PREFERRED[base]
        end

        cmd
      end

      def safe?(cmd)
        dangerous = [
          /rm\s+-rf?\s+\//, />\s*\/dev\/[sh]da/, /dd\s+if=/,
          /mkfs/, /fdisk/, /format\s+[a-z]:/i, /del\s+\/[sq]/i
        ]
        !dangerous.any? { |p| cmd.match?(p) }
      end

      def execute(cmd, timeout: 30)
        return Result.err("Dangerous command blocked") unless safe?(cmd)

        sanitized = sanitize(cmd)
        stdout = stderr = nil
        status = nil

        Timeout.timeout(timeout) do
          stdout, stderr, status = Open3.capture3(sanitized)
        end

        status.success? ? Result.ok(stdout) : Result.err("#{stderr}\n#{stdout}".strip)
      rescue Timeout::Error
        Result.err("Command timed out after #{timeout}s")
      rescue StandardError => e
        Result.err(e.message)
      end

      def which(cmd)
        stdout, _, status = Open3.capture3("which", cmd)
        status.success? ? stdout.strip : nil
      rescue StandardError
        nil
      end

      def zsh?
        ENV['SHELL']&.include?('zsh')
      end
    end
  end
end
