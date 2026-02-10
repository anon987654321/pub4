# frozen_string_literal: true

module MASTER
  # Shell integration - zsh-native patterns with OpenBSD support
  module Shell
    extend self

    BUILTINS = %w[cd pwd echo print printf export alias source].freeze
    
    OPENBSD_PATHS = %w[
      /usr/local/bin
      /usr/local/sbin
      /usr/bin
      /usr/sbin
      /bin
      /sbin
    ].freeze

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
      def detect_shell
        shell = ENV["SHELL"] || "/bin/sh"
        {
          path: shell,
          name: File.basename(shell),
          is_zsh: File.basename(shell) == "zsh",
          is_openbsd: RUBY_PLATFORM.include?("openbsd") || File.exist?("/bsd")
        }
      end

      def safe_env
        env = ENV.to_h.dup
        if detect_shell[:is_openbsd]
          env["PATH"] = (OPENBSD_PATHS + ENV["PATH"].to_s.split(":")).uniq.join(":")
        end
        env["SHELL"] ||= "/bin/sh"
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
    end
  end
end
