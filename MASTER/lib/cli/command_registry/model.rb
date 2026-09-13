# frozen_string_literal: true

module Master
  module CLI
    module CommandRegistry
      module_function

      # /model — show, list or switch the active model.
      def dispatch_model(agent:, config:, metrics:, root:, ctx: nil, arg: nil)
        arg = arg || arg_for(ctx)
        return list_models(root:, metrics:, agent:) if arg == "list"
        return "model: #{agent.model} (use /model list for available models)" if arg.empty?
        agent.model = arg; config.save!; "model: #{arg}"
      end

      def list_models(root:, metrics:, agent:)
        yml_path = File.join(root, "data", "models.yml")
        return "model: #{agent.model}" unless File.exist?(yml_path)
        data = Master.load_yaml(yml_path)
        tiers = data["models"] || {}
        current = agent.model.to_s
        model_lines = tiers.flat_map do |tier, ms|
          ms.to_a.map do |mod|
            marker = mod["id"].to_s == current ? "→ " : "  "
            "#{marker} [#{tier}] #{mod["id"]}"
          end
        end
        quality_lines = Array(metrics&.model_quality&.map do |mod, stat|
          "  #{mod}: #{stat[:calls]} calls, fail_rate=#{stat[:fail_rate]}"
        end)
        sections = ["available models:"] + model_lines
        sections += ["", "quality (this session):"] + quality_lines unless quality_lines.empty?
        sections.join("\n")
      end
    end
  end
end
