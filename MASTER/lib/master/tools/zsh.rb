# frozen_string_literal: true

require "tty-command"
require "shellwords"

module Master
  module Tools
    class Zsh
      TIER        = :dangerous
      NAME        = "zsh"
      DESCRIPTION = "Execute a zsh command in the project root."
      BLOCKLIST   = Security::Permissions::BLOCKLIST

      def initialize(root:, governor:, event_bus: nil)
        @root     = root
        @governor = governor
        @bus      = event_bus
        @cmd      = TTY::Command.new(printer: :null)
      end

      def call(command:)
        return Result.err("blocked command: #{command}", category: :validation) if blocked?(command)

        perm = @governor.permit?(NAME, TIER, command)
        return perm if perm.err?

        @bus&.publish("tool:before", tool: NAME, command:)

        zdotdir = File.writable?("/tmp") ? "/tmp" : Dir.home
        wrapped = "#!/usr/bin/env zsh\nset -euo pipefail\nsetopt nullglob extendedglob\nexport ZDOTDIR=#{Shellwords.escape(zdotdir)}\nexport LC_ALL=C.UTF-8\ncd #{Shellwords.escape(@root)}\n#{command}\n"

        out, err = @cmd.run!("zsh", input: wrapped)
        @bus&.publish("tool:after", tool: NAME, exit_code: out.exit_status)

        if out.exit_status != 0
          Result.err("zsh: exit #{out.exit_status}\n#{err.to_s.strip}", category: :unknown)
        else
          Result.ok(out.to_s.strip)
        end
      rescue TTY::Command::ExitError => e
        Result.err("zsh: #{e.message}", category: :unknown)
      end

      private

      def blocked?(command)
        BLOCKLIST.any? { |b| command.include?(b) }
      end
    end
  end
end
