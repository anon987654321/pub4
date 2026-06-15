# frozen_string_literal: true

require "open3"

module Master
  module Reach
    # CE04: thin wrapper to exec DEPLOY/postpro/postpro.rb.
    class Postpro
      NAME = "postpro".freeze

      def initialize(root: Dir.pwd, event_bus: nil)
        @root = root
        @bus = event_bus
      end

      def process(input_path, preset: nil, stock: nil)
        script = File.expand_path("../../DEPLOY/postpro/postpro.rb", Master::ROOT)
        return Result.err("postpro.rb not found") unless File.exist?(script)
        args = [script, input_path.to_s]
        args += ["--preset", preset] if preset
        args += ["--stock", stock] if stock
        out, status = Open3.capture2e(RbConfig.ruby, *args)
        status.success? ? Result.ok(out) : Result.err(out)
      end
    end
  end
end