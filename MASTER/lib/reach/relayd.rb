# frozen_string_literal: true

module Master
  module Reach
    # CE07: parse relayd.conf, check health endpoints, reload.
    class Relayd
      NAME = "relayd".freeze
      CONF_PATH = "/etc/relayd.conf".freeze

      def initialize(root: Dir.pwd, event_bus: nil)
        @root = root
        @bus = event_bus
      end

      def parse_config(path: CONF_PATH)
        return Result.err("relayd.conf not found") unless File.exist?(path)
        lines = File.readlines(path).grep_v(/^\s*#/)
        tables = lines.grep(/table\s+/).map(&:strip)
        Result.ok({ tables:, lines: lines.size })
      end

      def reload
        Reach::Vps.new(root: @root).run("doas rcctl reload relayd")
      end
    end
  end
end