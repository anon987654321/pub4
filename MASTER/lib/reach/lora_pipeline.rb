# frozen_string_literal: true

require "open3"
require "yaml"

module Master
  module Reach
    # Local FLUX LoRA pipeline for pub4/lora — Ruby orchestration, ai-toolkit train boundary only.
    module LoraPipeline
      CONFIG_PATH = MasterPaths.data("lora_pipeline.yml").freeze

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
        config.fetch("modes", {}).fetch(mode.to_s, "--#{mode}")
      end

      def run(mode: "check")
        script = orchestrator
        unless File.file?(script)
          return Result.err("warn: lora orchestrator missing at #{script}", category: :validation)
        end

        argv = [script, flag(mode)]
        out, status = Open3.capture2e(*argv, chdir: File.dirname(script))
        body = out.strip
        status.success? ? Result.ok(body) : Result.err(body.empty? ? "warn: lora #{mode} failed" : body, category: :infrastructure)
      rescue StandardError => e
        Result.err("warn: lora #{mode} #{e.class}: #{e.message}", category: :infrastructure)
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
          "modes: #{config.fetch('modes', {}).keys.join(', ')}",
        ].join("\n")
      end
    end
  end
end