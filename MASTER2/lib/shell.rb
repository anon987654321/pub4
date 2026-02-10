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

    OPENBSD_PATHS = %w[
      /usr/local/bin
      /usr/bin
      /bin
      /usr/sbin
      /sbin
      /usr/X11R6/bin
      /usr/local/sbin
    ].freeze

    class << self
      def openbsd?
        RUBY_PLATFORM.include?("openbsd")
      end

      def default_path
        openbsd? ? OPENBSD_PATHS.join(":") : ENV["PATH"]
      end

      def zsh_env
        env = ENV.to_h.dup
        env["SHELL"] = which("zsh") || "/bin/zsh" if zsh?
        env["PATH"] = default_path if openbsd?
        env["LC_ALL"] = "en_US.UTF-8"
        env["LANG"] = "en_US.UTF-8"
        env
      end

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

        stdout, stderr, status = nil
        Timeout.timeout(timeout) do
          stdout, stderr, status = Open3.capture3(zsh_env, sanitized)
        end

        status.success? ? Result.ok(stdout) : Result.err("#{stderr}\n#{stdout}".strip)
      rescue Timeout::Error
        Result.err("Command timed out after #{timeout}s")
      rescue StandardError => e
        Result.err(e.message)
      end

      def which(cmd)
        path = `which #{cmd} 2>/dev/null`.strip
        path.empty? ? nil : path
      end

      def zsh?
        ENV['SHELL']&.include?('zsh')
      end
    end
  end
end
