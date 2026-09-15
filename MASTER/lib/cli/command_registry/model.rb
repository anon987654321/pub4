# frozen_string_literal: true

require_relative "../routing/model_catalog"

module Master
  module CLI
    module CommandRegistry
      module_function

      # /model — show, list or switch the active model.
      def dispatch_model(agent:, config:, metrics:, root:, ctx: nil, arg: nil)
        arg = arg || arg_for(ctx)
        return list_models(root:, metrics:, agent:) if arg == "list"
        return "model: #{agent.model}; /model list names the others" if arg.empty?

        resolved = Master::CLI::Routing::ModelCatalog.resolve(
          arg,
          root:,
          local_models: agent.respond_to?(:candidate_models) ? agent.candidate_models : []
        )
        agent.model = resolved
        config.save!
        "model: #{agent.model}"
      rescue ArgumentError => e
        "model: #{e.message}"
      end

      # A table: one row per model, its tiers in the second column, and an
      # arrow on the one in use.
      def list_models(root:, metrics:, agent:)
        yml_path = File.join(root, "data", "models.yml")
        return "model: #{agent.model}" unless File.exist?(yml_path)

        tiers_by_id = (Master.load_yaml(yml_path)["models"] || {}).each_with_object(Hash.new { |h, k| h[k] = [] }) do |(tier, rows), out|
          rows.to_a.each { |row| out[row["id"].to_s] << tier }
        end
        width = tiers_by_id.keys.map(&:length).max.to_i
        current = agent.model.to_s
        lines = tiers_by_id.map { |id, tiers| "#{id == current ? '→' : ' '} #{id.ljust(width)}  #{tiers.uniq.join(', ')}" }
        quality = Array(metrics&.model_quality&.map { |mod, stat| "  #{mod}: #{stat[:calls]} calls, fail rate #{stat[:fail_rate]}" })
        lines += ["", "this session:"] + quality unless quality.empty?
        lines.unshift("active: #{current}")
        lines.unshift("models: #{tiers_by_id.length}")
        lines.join("\n")
      end
    end
  end
end
