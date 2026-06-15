# frozen_string_literal: true

require "open3"

module Master
  module Reach
    # CE03: thin wrapper to exec DEPLOY/repligen.rb.
    class Replicate
      NAME = "replicate".freeze

      def initialize(root: Dir.pwd, event_bus: nil)
        @root = root
        @bus = event_bus
      end

      def generate(prompt, **opts)
        script = File.expand_path("../../DEPLOY/repligen.rb", Master::ROOT)
        return Result.err("repligen.rb not found") unless File.exist?(script)
        args = [script, prompt.to_s]
        opts.each { |k, v| args << "--#{k}" << v.to_s }
        out, status = Open3.capture2e(RbConfig.ruby, *args)
        status.success? ? Result.ok(out) : Result.err(out)
      end
    end
  end
end