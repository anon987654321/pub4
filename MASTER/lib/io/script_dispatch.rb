# frozen_string_literal: true

require "open3"
require "shellwords"
require "rbconfig"
require "bundler"
require_relative "../boot/paths"
require_relative "../result"
require_relative "exec"

module Master
  module Io
    # Single Open3 entrypoint for MASTER/tools/*.rb scripts (replicate, postpro, …).
    module ScriptDispatch
      module_function

      def run(root:, tool:, arg: "", env: {})
        requested_root = File.expand_path(root.to_s.empty? ? Dir.pwd : root)
        script = script_path(requested_root, tool)
        return Result.err("#{tool}: missing tool entrypoint #{script}", category: :validation) unless File.file?(script)

        argv = Shellwords.split(arg.to_s)
        cmd = env.empty? ? [RbConfig.ruby] : [env.transform_keys(&:to_s).transform_values(&:to_s), RbConfig.ruby]
        runner = lambda do
          Master::Io::Exec.capture2e(
            *cmd,
            script,
            *argv,
            chdir: working_directory(requested_root, script),
          )
        end
        out, status = Bundler.with_unbundled_env(&runner)
        status.success? ? Result.ok(out.strip) : Result.err("#{tool}: exit=#{status.exitstatus}\n#{out.strip}")
      rescue ArgumentError => e
        Result.err("#{tool}: bad arguments: #{e.message}", category: :validation)
      rescue StandardError => e
        Result.err("#{tool}: #{e.class}: #{e.message}", category: :infrastructure)
      end

      # Launch MASTER from its own directory, the pub4 workspace root,
      # or another repository it operates on. Media entrypoints stay
      # discoverable in every case.
      def script_path(requested_root, tool)
        # Canonical tool entrypoints live at MASTER/tools/<tool>/<tool>.rb.
        # Flat tools/<tool>.rb and the old STUDIO/<tool>/<tool>.rb location are
        # compatibility paths only.
        candidates = [requested_root, MasterPaths.repo, MasterPaths.root].uniq.flat_map do |candidate|
          [
            File.join(candidate, "tools", tool, "#{tool}.rb"),
            File.join(candidate, "tools", "#{tool}.rb"),
            File.join(candidate, "STUDIO", tool, "#{tool}.rb")
          ]
        end
        candidates.find { |candidate| File.file?(candidate) } || candidates.first
      end

      def working_directory(requested_root, script)
        # A flat tools/<tool>.rb entry keeps the workspace-root convention. A
        # nested tools/<tool>/<tool>.rb entry owns its directory because that is
        # where media assets, scratch, samples and project state live.
        tools_root = File.join(requested_root, "tools")
        if script.start_with?(tools_root + File::SEPARATOR)
          relative = script.delete_prefix(tools_root + File::SEPARATOR)
          return File.dirname(script) if relative.include?(File::SEPARATOR)
          return File.expand_path("..", requested_root)
        end

        studio_root = File.join(MasterPaths.repo, "STUDIO")
        if script.start_with?(studio_root + File::SEPARATOR)
          relative = script.delete_prefix(studio_root + File::SEPARATOR)
          return File.dirname(script) if relative.include?(File::SEPARATOR)
          return MasterPaths.repo
        end

        master_tools = File.join(MasterPaths.repo, "MASTER", "tools")
        if script.start_with?(master_tools + File::SEPARATOR)
          relative = script.delete_prefix(master_tools + File::SEPARATOR)
          return File.dirname(script) if relative.include?(File::SEPARATOR)
        end

        return requested_root if File.directory?(requested_root)

        MasterPaths.repo
      end

    end
  end
end
