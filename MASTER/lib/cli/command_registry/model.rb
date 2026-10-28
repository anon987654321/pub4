# frozen_string_literal: true

module Master
  module CLI
    module CommandRegistry
      module_function

      # /model — show, list or switch the active model. `/model auth` connects
      # the subscription lanes those models are served through.
      def dispatch_model(agent:, config:, metrics:, root:, ctx: nil, arg: nil)
        arg = arg || arg_for(ctx)
        word, rest = subcommand({ args: arg })
        return dispatch_auth(ctx: rest) if word == "auth"
        return trajectory_lab(root:) if word == "lab"
        return list_models(root:, metrics:, agent:) if arg == "list"
        return model_health(agent:) if arg == "health"
        return compute_models(agent:, root:) if arg == "compute"
        if arg == "benchmark" || arg.start_with?("benchmark ")
          benchmark_args = arg.delete_prefix("benchmark").strip
          return ModelBenchmark.new(agent:, router: model_router_of(agent), metrics:, root:).run(benchmark_args)
        end
        return "model: #{agent.model}; #{Io::LaneSelection.primary_report(saved: config["model"])}; /model list names the others" if arg.empty?

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
        rows = model_rows(ids:, current:, tiers_by_id:, router:)
        rows.join("\n") + model_list_footer(router, metrics)
      end

      def model_rows(ids:, current:, tiers_by_id:, router:)
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

      # Summarize measured provider outcomes without printing raw provider
      # errors, response bodies or credentials. Detailed diagnostic events remain
      # available through /diag; this surface answers whether the pool is healthy.
      def model_health(agent:)
        router = model_router_of(agent)
        return "model health: router unavailable" unless router

        pool = router.compute_pool if router.respond_to?(:compute_pool)
        return "model health: telemetry unavailable" unless pool&.respond_to?(:snapshot)

        stats = pool.snapshot
        measured = stats.filter_map do |id, raw|
          next unless raw.is_a?(Hash)

          calls = raw.fetch(:calls, 0).to_i
          next unless calls.positive?

          successes = raw.fetch(:successes, 0).to_i
          failures = raw.fetch(:failures, 0).to_i
          latency = raw.fetch(:latency_ms, 0).to_f
          latency = nil unless latency.finite? && latency.positive? && successes.positive?
          {
            id: id.to_s,
            calls:,
            successes:,
            failures:,
            rate: successes.fdiv(calls),
            latency_ms: latency,
          }
        end
        return "model health: no recorded calls yet; /model compute lists reachable lanes" if measured.empty?

        total_calls = measured.sum { |row| row[:calls] }
        total_successes = measured.sum { |row| row[:successes] }
        total_failures = measured.sum { |row| row[:failures] }
        total_rate = total_successes.fdiv(total_calls)
        lines = [
          "model health: #{measured.size} models, #{total_calls} calls, " \
          "success=#{(total_rate * 100).round(1)}%, failures=#{total_failures}",
        ]
        measured.sort_by { |row| [-row[:failures], -row[:calls], row[:id]] }.first(30).each do |row|
          average = row[:latency_ms] ? "#{row[:latency_ms].round}ms" : "n/a"
          lines << "  #{row[:id]}  calls=#{row[:calls]} ok=#{row[:successes]} " \
                   "fail=#{row[:failures]} success=#{(row[:rate] * 100).round(1)}% avg_ok=#{average}"
        end
        hidden = measured.size - 30
        lines << "  … #{hidden} more models" if hidden.positive?
        lines.join("\n")
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "command_registry.model_health")
        "model health: unavailable (#{e.class})"
      end

      def trajectory_lab(root:)
        path = File.join(root, ".master", "trajectories", "trajectories.ndjson")
        Master::AI::Trajectory::Laboratory.render(input: path)
      rescue StandardError => e
        "model0: lab failed — #{e.class}: #{e.message}"
      end

      def compute_models(agent:, root:)
        router = model_router_of(agent)
        return "compute: router unavailable" unless router

        rows = router.compute_pool.inventory(task_type: :code_generation)
        return "compute: no reachable models" if rows.empty?

        rows.map do |row|
          quota = row[:quota_remaining].nil? ? row[:quota_state] : "quota=#{row[:quota_remaining]}"
          rate = row[:success_rate].nil? ? "unmeasured" : "success=#{(row[:success_rate] * 100).round}%"
          calls = row[:calls].to_i
          latency = row[:latency_ms].to_f
          average = latency.finite? && latency.positive? ? "avg_ok=#{latency.round}ms" : "avg_ok=n/a"
          "#{row[:rank]}. #{row[:id]}  #{row[:lane]}  #{quota}  #{rate} calls=#{calls} #{average}"
        end.join("\n")
      end

      def model_tiers_by_id(root)
        rows = Master.model_tiers(root:) || {}
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
