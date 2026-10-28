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

      # Public tool names resolve to one canonical entrypoint. LoRA lives under
      # STUDIO/replicate because that tree owns the whole provider boundary.
      TOOL_ENTRYPOINTS = { "lora" => File.join("replicate", "lora", "lora.rb") }.freeze

      def run(root:, tool:, arg: "", env: {})
        requested_root = File.expand_path(root.to_s.empty? ? Dir.pwd : root)
        script = script_path(requested_root, tool)
        return Result.err("#{tool}: missing tool entrypoint #{script}", category: :validation) unless File.file?(script)

        argv = Shellwords.split(arg.to_s)
        cmd = env.empty? ? [RbConfig.ruby] : [env.transform_keys(&:to_s).transform_values(&:to_s), RbConfig.ruby]
        out, status = Master::Io::Exec.capture2e(*cmd, script, *argv, chdir: working_directory(requested_root, script))
        status.success? ? Result.ok(out.strip) : Result.err("#{tool}: exit=#{status.exitstatus}\n#{out.strip}")
      rescue ArgumentError => e
        Result.err("#{tool}: bad arguments: #{e.message}", category: :validation)
      rescue StandardError => e
        Result.err("#{tool}: #{e.class}: #{e.message}", category: :infrastructure)
      end

      # Resolve known Studio tools first; explicit aliases name tools whose
      # canonical entrypoint is nested below their provider tree. Other
      # registered tools retain the existing MASTER/tools and workspace tool
      # layouts. Every candidate is built from a fixed root and a single name.
      def script_path(requested_root, tool)
        name = tool.to_s
        return File.join(requested_root, "MASTER", "tools", "invalid.rb") unless name.match?(/\A[a-zA-Z0-9_-]+\z/)

        roots = [requested_root, MasterPaths.repo, MasterPaths.root].uniq
        entrypoint = TOOL_ENTRYPOINTS.fetch(name) { File.join(name, "#{name}.rb") }
        studio_candidates = roots.map { |candidate| File.join(candidate, "STUDIO", entrypoint) }
        studio = studio_candidates.find { |candidate| File.file?(candidate) }
        return studio if studio

        master_candidates = roots.flat_map do |candidate|
          [
            File.join(candidate, "MASTER", "tools", "#{name}.rb"),
            File.join(candidate, "tools", "#{name}.rb"),
            File.join(candidate, "tools", name, "#{name}.rb"),
          ]
        end
        master_candidates.find { |candidate| File.file?(candidate) } || studio_candidates.first
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
