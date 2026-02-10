# frozen_string_literal: true

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
        output = nil
        
        Timeout.timeout(timeout) do
          output = `#{sanitized} 2>&1`
        end

        $?.success? ? Result.ok(output) : Result.err(output)
      rescue Timeout::Error
        Result.err("Command timed out after #{timeout}s")
      rescue => e
        Result.err(e.message)
      end

      def which(cmd)
        path = `which #{cmd} 2>/dev/null`.strip
        path.empty? ? nil : path
      end

      def zsh?
        ENV['SHELL']&.include?('zsh')
      end

      def ensure_openbsd_path!
        paths = %w[/usr/local/bin /usr/X11R6/bin /usr/local/sbin]
        current = ENV["PATH"].to_s.split(":")
        missing = paths - current
        ENV["PATH"] = (missing + current).join(":") if missing.any?
      end
    end
  end
end
