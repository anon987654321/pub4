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
        out, status = runner.call
        status.success? ? Result.ok(out.strip) : Result.err("#{tool}: exit=#{status.exitstatus}\n#{out.strip}")
      rescue ArgumentError => e
        Result.err("#{tool}: bad arguments: #{e.message}", category: :validation)
      rescue StandardError => e
        Result.err("#{tool}: #{e.class}: #{e.message}", category: :infrastructure)
      end

      # Resolve only the canonical Studio entrypoint. A compatibility link under
      # MASTER/tools would hide a boundary violation, so there is deliberately no fallback.
      def script_path(requested_root, tool)
        roots = [requested_root, MasterPaths.repo, MasterPaths.root].uniq
        candidates = roots.map { |candidate| File.join(candidate, "STUDIO", tool, "#{tool}.rb") }
        candidates.find { |candidate| File.file?(candidate) } || candidates.first
      end

      def working_directory(requested_root, script)
        [requested_root, MasterPaths.repo, MasterPaths.root].uniq.each do |candidate|
          studio_root = File.join(candidate, "STUDIO")
          next unless script.start_with?(studio_root + File::SEPARATOR)

          relative = script.delete_prefix(studio_root + File::SEPARATOR)
          return File.dirname(script) if relative.include?(File::SEPARATOR)
          return candidate
        end

        return requested_root if File.directory?(requested_root)

        MasterPaths.repo
      end

    end
  end
end
