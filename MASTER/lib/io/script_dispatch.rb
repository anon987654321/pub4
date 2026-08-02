# frozen_string_literal: true

require "open3"
require "shellwords"
require "rbconfig"
require_relative "../boot/paths"
require_relative "../result"
require_relative "exec"

module Master
  module Io
    # Single Open3 entrypoint for MASTER/tools/*.rb scripts (repligen, postpro, …).
    module ScriptDispatch
      module_function

      def run(root:, tool:, arg: "", env: {})
        requested_root = File.expand_path(root.to_s.empty? ? Dir.pwd : root)
        script = script_path(requested_root, tool)
        return Result.err("#{tool}: missing tool entrypoint #{script}", category: :validation) unless File.file?(script)

        argv = Shellwords.split(arg.to_s)
        cmd = env.empty? ? [RbConfig.ruby] : [env.transform_keys(&:to_s).transform_values(&:to_s), RbConfig.ruby]
        out, status = Master::Io::Exec.capture2e(
          *cmd,
          script,
          *argv,
          chdir: working_directory(requested_root, script),
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

      # Launch MASTER from its own directory, the pub4 workspace root,
      # or another repository it operates on. Media entrypoints stay
      # discoverable in every case.
      def script_path(requested_root, tool)
        # A tool entrypoint is either tools/<tool>.rb or, once it grows its own
        # directory, tools/<tool>/<tool>.rb (e.g. postpro/postpro.rb). Media
        # tools (dilla, postpro, repligen) were extracted out of MASTER/tools/
        # into the sibling STUDIO/<tool>/<tool>.rb — checked last so anything
        # still living under MASTER/tools/ keeps taking priority.
        candidates = [requested_root, MasterPaths.root].uniq.flat_map do |candidate|
          [File.join(candidate, "tools", "#{tool}.rb"),
           File.join(candidate, "tools", tool, "#{tool}.rb")]
        end
        candidates << File.join(MasterPaths.repo, "STUDIO", tool, "#{tool}.rb")
        candidates.find { |candidate| File.file?(candidate) } || candidates.first
      end

      def working_directory(requested_root, script)
        # Any tool under tools/ (flat or in its own subdir) runs from the repo
        # root — the parent of the MASTER checkout — so relative asset/config
        # paths resolve identically regardless of the tool's file layout.
        return File.expand_path("..", requested_root) if script.start_with?(File.join(requested_root, "tools") + File::SEPARATOR)
        # STUDIO/<tool> scripts run from their own directory — that's where
        # their scratch/.cache, samples/, and project/ state live.
        return File.dirname(script) if script.start_with?(File.join(MasterPaths.repo, "STUDIO") + File::SEPARATOR)
        return requested_root if File.directory?(requested_root)

        MasterPaths.repo
      end
    end
  end
end
