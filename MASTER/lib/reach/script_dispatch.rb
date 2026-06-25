# frozen_string_literal: true

require "open3"
require "shellwords"
require "rbconfig"

module Master
  module Reach
    # Single Open3 entrypoint for MASTER/tools/*.rb scripts (repligen, postpro, …).
    module ScriptDispatch
      module_function

      def run(root:, tool:, arg: "")
        script = File.join(root, "tools", "#{tool}.rb")
        return Result.err("#{tool}: missing tool entrypoint #{script}", category: :validation) unless File.file?(script)

        argv = Shellwords.split(arg.to_s)
        out, status = Open3.capture2e(RbConfig.ruby, script, *argv, chdir: File.expand_path("..", root))
        status.success? ? Result.ok(out.strip) : Result.err("#{tool}: exit=#{status.exitstatus}\n#{out.strip}")
      rescue ArgumentError => e
        Result.err("#{tool}: bad arguments: #{e.message}", category: :validation)
      rescue StandardError => e
        Result.err("#{tool}: #{e.class}: #{e.message}", category: :infrastructure)
      end

      def run_string(root:, tool:, arg: "")
        run(root:, tool:, arg:).then { |r| r.ok? ? r.value! : r.message }
      end
    end
  end
end