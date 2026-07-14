# frozen_string_literal: true

require "open3"
require "shellwords"
require "rbconfig"
require_relative "../master_paths"
require_relative "../result"
require_relative "exec"

module Master
  module Reach
    # Single Open3 entrypoint for MASTER/tools/*.rb scripts (repligen, postpro, …).
    module ScriptDispatch
      module_function

      def run(root:, tool:, arg: "")
        requested_root = File.expand_path(root.to_s.empty? ? Dir.pwd : root)
        script = script_path(requested_root, tool)
        return Result.err("#{tool}: missing tool entrypoint #{script}", category: :validation) unless File.file?(script)

        argv = Shellwords.split(arg.to_s)
        out, status = Master::Reach::Exec.capture2e(
          RbConfig.ruby,
          script,
          *argv,
          chdir: working_directory(requested_root, script)
        )
        status.success? ? Result.ok(out.strip) : Result.err("#{tool}: exit=#{status.exitstatus}\n#{out.strip}")
      rescue ArgumentError => e
        Result.err("#{tool}: bad arguments: #{e.message}", category: :validation)
      rescue StandardError => e
        Result.err("#{tool}: #{e.class}: #{e.message}", category: :infrastructure)
      end

      def run_string(root:, tool:, arg: "")
        run(root:, tool:, arg:).then { |r| r.ok? ? r.value! : r.message }
      end

      # MASTER can be launched from its own directory, the pub4 workspace root,
      # or another repository it is operating on. Its media entrypoints remain
      # discoverable in every case.
      def script_path(requested_root, tool)
        candidates = [requested_root, MasterPaths.root].uniq.map do |candidate|
          File.join(candidate, "tools", "#{tool}.rb")
        end
        candidates.find { |candidate| File.file?(candidate) } || candidates.first
      end

      def working_directory(requested_root, script)
        return File.expand_path("..", requested_root) if File.dirname(script) == File.join(requested_root, "tools")
        return requested_root if File.directory?(requested_root)

        MasterPaths.repo
      end
    end
  end
end
