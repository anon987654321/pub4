<sub># frozen_string_literal: true

module Master
  module CLI
    module CommandRegistry
      module_function

      # /model — show, list or switch the active model.
      def dispatch_model(agent:, config:, metrics:, root:, ctx: nil, arg: nil)
        arg = arg || arg_for(ctx)
        return list_models(root:, metrics:, agent:) if arg == "list"
        return compute_models(agent:, root:) if arg == "compute"
        if arg == "benchmark" || arg.start_with?("benchmark ")
          benchmark_args = arg.delete_prefix("benchmark").strip
          return ModelBenchmark.new(agent:, router: model_router_of(agent), metrics:, root:).run(benchmark_args)
        end
        return "model: #{agent.model}; /model list names the others" if arg.empty?

        chosen, note = reachable_choice(agent, arg)
        agent.model = chosen
        config.save!
        ["model: #{agent.model}", note].compact.join("; ")
      rescue ArgumentError => e
        "model: #{e.message}"
      end

      # A model the pool cannot reach is refused with its fix, unless the pool
      # serves the same model through another lane: with only an OpenRouter key,
      # gemini-2.5-flash becomes google/gemini-2.5-flash.
      def reachable_choice(agent, name)
        router = model_router_of(agent)
        return [name, nil] if router.nil? || Review::Agent::ModelOverride::LOCAL_TIER_NAMES.include?(name.downcase)

        reason = router.unreachable_reason(name, wait: true)
        return [name, nil] unless reason

        twin = router.pool.find { |id| id.delete_suffix(":free").end_with?("/#{name}") }
        raise ArgumentError, "#{name} is out of reach: #{reason}" unless twin

        [twin, "#{name} itself needs: #{reason}"]
      end

      # A table: one row per model the pool can reach, its tiers or its lane in
      # the second column, and an arrow on the one in use. Under it, what would
      # add more.
      def list_models(root:, metrics:, agent:)
        router = model_router_of(agent)
        tiers_by_id = model_tiers_by_id(root)
        current = agent.model.to_s
        ids = router ? router.pool(wait: true) : tiers_by_id.keys
        ids = [current] + ids unless current.empty? || ids.include?(current)
        rows = model_rows(ids, current, tiers_by_id, router)
        rows.join("\n") + model_list_footer(router, metrics)
      end

      def model_rows(ids, current, tiers_by_id, router)
        width = ids.map(&:length).max.to_i
        ids.map do |id|
          label = tiers_by_id.fetch(id) { [router&.lane_label(id)].compact }.uniq.join(", ")
          "#{id == current ? '→' : ' '} #{id.ljust(width)}  #{label}".rstrip
        end
      end

      def model_list_footer(router, metrics)
        growth = Array(router&.pool_growth)
        quality = Array(metrics&.model_quality&.map do |mod, stat|
          "  #{mod}: #{stat[:calls]} calls, fail rate #{stat[:fail_rate]}"
        end)
        footer = growth.empty? ? [] : ["", "more with:"] + growth.map { |fix| "  #{fix}" }
        footer += ["", "this session:"] + quality unless quality.empty?
        footer.empty? ? "" : "\n#{footer.join("\n")}"
      end

      def compute_models(agent:, root:)
        router = model_router_of(agent)
        return "compute: router unavailable" unless router

        ids = router.pool(wait: true)
        ranked = router.compute_pool.rank(ids, task_type: :code_generation)
        ranked.map.with_index { |id, index| "#{index + 1}. #{id}  #{router.lane_label(id)}" }.join("\n")
      end

      def model_tiers_by_id(root)
        yml_path = File.join(root, "data", "models.yml")
        rows = File.exist?(yml_path) ? (Master.load_yaml(yml_path)["models"] || {}) : {}
        rows.each_with_object(Hash.new { |h, k| h[k] = [] }) do |(tier, entries), out|
          entries.to_a.each { |row| out[row["id"].to_s] << tier }
        end
      end

      def model_router_of(agent)
        router = agent.model_router if agent.respond_to?(:model_router)
        router if router.respond_to?(:unreachable_reason)
      end
    end
  end
end

</sub>