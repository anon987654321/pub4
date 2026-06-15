# frozen_string_literal: true

require "open3"

module Master
  module Reach
    # CE06: query NSD zone file, validate records, reload zone.
    class Nsd
      NAME = "nsd".freeze

      def initialize(root: Dir.pwd, event_bus: nil)
        @root = root
        @bus = event_bus
      end

      def query(name, type: "A")
        run_doas("nsd-control", "status")
        run_doas("dig", "@127.0.0.1", name, type)
      end

      def reload
        run_doas("rcctl", "reload", "nsd")
      end

      private

      def run_doas(*args)
        out, status = Open3.capture2e("doas", *args)
        status.success? ? Result.ok(out) : Result.err(out.strip)
      end
    end
  end
end