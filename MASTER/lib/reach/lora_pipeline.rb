# frozen_string_literal: true

require "yaml"
require_relative "../master_paths"
require_relative "../result"
require_relative "exec"

module Master
  module Reach
    # Local FLUX LoRA pipeline for pub4/lora — Ruby orchestration, ai-toolkit train boundary only.
    module LoraPipeline
      CONFIG_PATH = MasterPaths.data("lora_pipeline.yml").freeze
      TIMEOUTS = { "check" => 120, "generate" => 3_600, "postpro" => 3_600, "train" => 86_400 }.freeze

      module_function

      def config
        @config ||= YAML.load_file(CONFIG_PATH) || {}
      rescue StandardError
        {}
      end

      def repo_path(rel)
        File.join(MasterPaths.repo, rel.to_s)
      end

      def orchestrator
        repo_path(config.fetch("orchestrator", "lora/training/ragnhild/ai_toolkit/run_generate.sh"))
      end

      def flag(mode)
        config.fetch("mode_flags", {}).fetch(mode.to_s, "--#{mode}")
      end

      def run(mode: "check", prompt: nil)
        script = orchestrator
        unless File.file?(script)
          return Result.err("warn: lora orchestrator missing at #{script}", category: :validation)
        end

        argv = [script, flag(mode)]
        env = prompt.to_s.strip.empty? ? {} : { "RAGNHILD_PROMPT" => prompt.to_s.strip }
        out, status = Exec.capture2e(env, *argv, chdir: File.dirname(script), timeout: TIMEOUTS.fetch(mode.to_s, 3_600))
        body = out.strip
        status.success? ? Result.ok(body) : Result.err(body.empty? ? "warn: lora #{mode} failed" : body, category: :infrastructure)
      rescue StandardError => e
        Result.err("warn: lora #{mode} #{e.class}: #{e.message}", category: :infrastructure)
      end

      def weights_dir
        repo_path(config.fetch("weights_dir", "lora/training/ragnhild/ai_toolkit/weights/ragnhild_v2"))
      end

      def checkpoints
        dir = weights_dir
        return [] unless Dir.exist?(dir)

        Dir.children(dir)
          .select { |name| name.end_with?(".safetensors") }
          .map { |name| File.join(dir, name) }
          .sort_by { |path| File.mtime(path) }
      end

      # A checkpoint whose mtime is still advancing is being written by an
      # active training step; picking it mid-write would hand back a
      # truncated safetensors file.
      def safe_checkpoint?(path, quiet_for: 30)
        Time.now - File.mtime(path) >= quiet_for
      end

      def latest_safe_checkpoint
        checkpoints.reverse.find { |path| safe_checkpoint?(path) }
      end

      def training_pid_path
        File.join(File.dirname(orchestrator), "train.pid")
      end

      def training_in_progress?
        pid = File.read(training_pid_path).to_s.strip.to_i
        return false if pid <= 0

        begin
          Process.kill(0, pid)
          true
        rescue Errno::ESRCH
          false
        rescue Errno::EPERM
          true
        end
      rescue StandardError
        false
      end

      # :ready holds a checkpoint safe to sample from now; :training and
      # :writing distinguish "come back later" from "a checkpoint exists but
      # hasn't settled"; :untrained means no run has produced weights yet.
      def readiness
        return { state: :ready, checkpoint: latest_safe_checkpoint } if latest_safe_checkpoint
        return { state: :training, checkpoint: nil } if training_in_progress?
        return { state: :writing, checkpoint: nil } if checkpoints.any?

        { state: :untrained, checkpoint: nil }
      end

      def summary
        helpers = config.fetch("helpers", {})
        upstream = config.fetch("upstream", {})
        [
          "ok: lora pipeline (Ruby orchestration)",
          "orchestrator: #{config['orchestrator']}",
          "gate: #{helpers['gate_check']}",
          "render: #{helpers['render_config']}",
          "postpro: #{helpers['postpro']}",
          "upstream: #{upstream['name']} #{upstream['entrypoint']} — #{upstream['note']}",
          "images: #{config['images_root']}",
          "weights: #{config['weights_dir']}",
          "modes: #{config.fetch('mode_flags', {}).keys.join(', ')}",
        ].join("\n")
      end
    end
  end
end
