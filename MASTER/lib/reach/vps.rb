# frozen_string_literal: true

require "open3"

module Master
  module Reach
    # CE05: SSH command runner against brgen.no with output capture.
    class Vps
      NAME = "vps".freeze
      DEFAULT_HOST = "brgen.no".freeze

      def initialize(root: Dir.pwd, event_bus: nil)
        @root = root
        @bus = event_bus
      end

      def run(command, host: DEFAULT_HOST, user: ENV.fetch("MASTER_SSH_USER", "root"))
        target = "#{user}@#{host}"
        out, status = Open3.capture2e("ssh", target, command.to_s)
        @bus&.publish("reach:vps", host:, ok: status.success?)
        status.success? ? Result.ok(out) : Result.err(out.strip)
      rescue StandardError => e
        Result.err("vps: #{e.message}")
      end
    end
  end
end