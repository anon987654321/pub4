# frozen_string_literal: true

require "yaml"
require_relative "../../io/atomic_write"
require_relative "../../io/model_quota"
require_relative "../../io/quota_gate"
require_relative "../../io/catalog_index"

module Master
  module Core
    module Routing
      # Live compute economics for model selection.
      #
      # MASTER owns the decision; providers only expose compute. Static model
      # scores remain the baseline while observed outcomes continuously adjust
      # quality and latency. Free/local lanes are not hard-coded winners: they
      # win when their measured utility is actually better.
      class ComputePool
        include Master::Io::AtomicWrite
        Candidate = Struct.new(:id, :quality, :speed, :cost, :context_window,
          :availability, :tool_support, :success_rate, :latency_factor, :score,
          keyword_init: true)

        DEFAULTS = {
          quality: 0.5,
          speed: 0.5,
          cost: 0.5,
          context_window: 128_000,
          availability: 1.0,
          tool_support: 0.5,
        }.freeze

        def initialize(router:, root: Master::ROOT)
          @router = router
          @root = root
          @rules = load_rules
          @stats = load_stats
          @catalog = nil
          @mutex = Mutex.new
        end

        def rank(ids, task_type: :exploration, empirical_best: nil)
          candidates = Array(ids).filter_map { |id| candidate(id) }
          candidates.sort_by { |entry| [-utility(entry, task_type:, empirical_best:), entry.id] }
            .map(&:id)
        end

        def select(ids, task_type: :exploration, empirical_best: nil)
          rank(ids, task_type:, empirical_best:).first
        end

        def refresh!
          @router.refresh_pool! if @router.respond_to?(:refresh_pool!)
          @catalog = nil
          @catalog_rows = nil
          self
        rescue StandardError => e
          Master::Ground::Swallow.log(e, context: "compute_pool.refresh")
          self
        end

        def inventory(task_type: :exploration, refresh: false)
          refresh! if refresh
          ids = @router.pool(wait: false)
          ranked = rank(ids, task_type:)
          ranked.each_with_index.map { |id, index| inventory_row(id, rank: index + 1, task_type:) }
        rescue StandardError => e
          Master::Ground::Swallow.log(e, context: "compute_pool.inventory")
          []
        end

        def record(model:, status:, latency_ms: nil, error: nil)
          key = model.to_s
          return if key.empty?

          @mutex.synchronize do
            stat = (@stats[key] ||= { calls: 0, successes: 0, failures: 0, latency_ms: 0.0, last_error: nil })
            stat[:calls] += 1
            if status.to_sym == :success
              stat[:successes] += 1
              stat[:latency_ms] = rolling_average(stat[:latency_ms], latency_ms.to_f, stat[:successes])
            else
              stat[:failures] += 1
              stat[:last_error] = error.to_s unless error.to_s.empty?
            end
            persist_stats
          end
        end

        def snapshot
          @mutex.synchronize do
            @stats.each_with_object({}) do |(model, stat), copy|
              copy[model] = stat.dup
            end
          end
        end

        private

        def candidate(id)
          row = model_row(id)
          return unless row

          score = row.fetch("score", {})
          success_rate, latency_factor = empirical_stats(id)
          Candidate.new(
            id: id.to_s,
            quality: score.fetch("quality", DEFAULTS[:quality]).to_f,
            speed: score.fetch("speed", DEFAULTS[:speed]).to_f,
            cost: score.fetch("cost", DEFAULTS[:cost]).to_f,
            context_window: row.fetch("context_window", DEFAULTS[:context_window]).to_i,
            availability: @router.reachable?(id) ? 1.0 : 0.0,
            tool_support: @router.tool_capable?(id) ? 1.0 : DEFAULTS[:tool_support],
            success_rate:,
            latency_factor:,
            score:,
          )
        rescue StandardError => e
          Master::Ground::Swallow.log(e, context: "compute_pool.candidate", model: id)
          nil
        end

        def empirical_stats(id)
          stat = @mutex.synchronize { @stats[id.to_s]&.dup }
          calls = stat&.fetch(:calls, 0).to_i
          successes = stat&.fetch(:successes, 0).to_i
          success_rate = calls.zero? ? 1.0 : successes.fdiv(calls)
          latency = stat&.fetch(:latency_ms, 0).to_f
          [success_rate, latency.zero? ? 1.0 : [1000.0 / [latency, 1000.0].max, 1.0].min]
        end

        def utility(entry, task_type:, empirical_best:)
          return 0.0 if entry.availability <= 0.0

          quality = entry.quality * entry.success_rate
          speed = entry.speed * entry.latency_factor
          economic_factor = [entry.cost, 0.1].max
          task_factor = task_factor(entry, task_type)
          empirical_factor = empirical_capability_factor(entry.id, task_type)
          empirical_factor *= 1.05 if entry.id == empirical_best.to_s

          # models.yml normalizes cost as economic value: 1.0 is free/local
          # compute and smaller values represent increasingly scarce spend.
          quality * entry.availability * speed * task_factor * empirical_factor *
            [entry.tool_support, 0.1].max * context_factor(entry.context_window) * economic_factor
        end

        def task_factor(entry, task_type)
          strengths = Array(@rules.dig("task_strengths", task_type.to_s))
          return 1.0 if strengths.empty?

          strength = strengths.count { |name| capability_match?(entry.id, name) }
          1.0 + [strength, 3].min * 0.04
        end

        def capability_match?(id, capability)
          text = "#{id} #{provider_for(id)}".downcase
          case capability.to_s
          when "local", "privacy", "offline" then id.start_with?("ollama:", "local:")
          when "fast" then text.match?(/flash|fast|lightning|small/)
          when "coding", "agentic" then text.match?(/code|coder|qwen|deepseek|claude|grok|glm|gpt/)
          when "reasoning" then text.match?(/reason|thinking|opus|pro|grok|deepseek/)
          when "long_context" then text.match?(/gemini|claude|qwen|agy/)
          else false
          end
        end

        def empirical_capability_factor(id, task_type)
          return 1.0 unless @router.respond_to?(:capability_score)

          score = @router.capability_score(id, task_type:)
          0.8 + (score.to_f * 0.4)
        rescue StandardError
          1.0
        end

        def provider_for(id)
          id.to_s.split(":", 2).first
        end

        def context_factor(window)
          [[window.fdiv(128_000), 1.25].min, 0.5].max
        end

        def model_row(id)
          static_model_row(id) || catalog_model_row(id) || dynamic_model_row(id)
        end

        def static_model_row(id)
          @rules.fetch("models", {}).values.flatten.find { |row| row.is_a?(Hash) && row["id"].to_s == id.to_s } ||
            @rules.fetch("model_defs", {}).values.find { |row| row.is_a?(Hash) && row["id"].to_s == id.to_s }
        end

        def catalog_model_row(id)
          source = catalog_source_for(id)
          return unless source
          rows = catalog_rows_for(source)
          row = rows[id.to_s]
          return unless row

          {
            "context_window" => row.fetch("context_length", 0).to_i.nonzero? || DEFAULTS[:context_window],
            "score" => catalog_score(row),
          }
        rescue StandardError => e
          Master::Ground::Swallow.log(e, context: "compute_pool.catalog_model", model: id)
          nil
        end

        def catalog_source_for(id)
          text = id.to_s
          return "openrouter" if text.include?("/")

          provider = @router.respond_to?(:api_provider_for) ? @router.api_provider_for(text) : provider_for(text)
          {
            "openai" => "openai",
            "gemini" => "gemini",
            "deepseek" => "deepseek",
            "xai" => "xai",
            "mistral" => "mistral",
          }[provider.to_s]
        rescue StandardError
          nil
        end

        def catalog_rows_for(source)
          @catalog_rows ||= {}
          return @catalog_rows[source] if @catalog_rows.key?(source)
          @catalog_rows[source] = if File.file?(Master::Io::CatalogIndex::DEFAULT_DB)
            catalog = (@catalog ||= Master::Io::CatalogIndex.new(db_path: Master::Io::CatalogIndex::DEFAULT_DB))
            catalog.search(nil, source:, limit: 5_000).each_with_object({}) { |row, index| index[row["id"].to_s] = row }
          else
            {}
          end
        end

        def dynamic_model_row(id)
          return unless id.to_s.start_with?("ollama:", "local:")
          {
            "context_window" => DEFAULTS[:context_window],
            "score" => { "quality" => DEFAULTS[:quality], "speed" => DEFAULTS[:speed], "cost" => 1.0 },
          }
        end

        def catalog_score(row)
          prompt = row["price_prompt"].to_f
          completion = row["price_completion"].to_f
          price = [prompt, completion].max
          {
            "quality" => catalog_quality(row),
            "speed" => catalog_speed(row),
            "cost" => price.zero? ? 1.0 : 1.0 / (1.0 + Math.log10(1.0 + price * 1_000_000)),
          }
        end

        def catalog_quality(row)
          text = "#{row['id']} #{row['name']} #{row['description']} #{row['tags']}".downcase
          return 0.88 if text.match?(/reason|thinking|opus|pro|ultra|large|70b|72b|120b|235b/)
          return 0.82 if text.match?(/coder|code|qwen|deepseek|gemini|claude|gpt|grok/)
          0.68
        end

        def catalog_speed(row)
          text = "#{row['id']} #{row['name']} #{row['description']} #{row['tags']}".downcase
          return 0.92 if text.match?(/flash|fast|mini|small|nano|lightning/)
          return 0.65 if text.match?(/large|70b|72b|120b|235b|opus/)
          0.75
        end

        def stats_path
          File.join(@root, "runtime", "telemetry", "compute_pool.yml")
        end

        def load_stats
          return {} unless File.file?(stats_path)
          raw = Master.load_yaml(stats_path) || {}
          raw.each_with_object({}) do |(model, stat), out|
            out[model.to_s] = stat.to_h.transform_keys(&:to_sym)
          end
        rescue StandardError => e
          Master::Ground::Swallow.log(e, context: "compute_pool.load_stats")
          {}
        end

        def inventory_row(id, rank:, task_type:)
          stat = @mutex.synchronize { @stats[id.to_s]&.dup || {} }
          {
            id: id.to_s,
            rank:,
            lane: @router.lane_label(id),
            reachable: true,
            task: task_type.to_sym,
            calls: stat.fetch(:calls, 0).to_i,
            success_rate: success_rate(stat),
            latency_ms: stat.fetch(:latency_ms, 0).to_f,
            quota_remaining: quota_remaining(id),
            quota_state: quota_state(id),
          }
        end

        def success_rate(stat)
          calls = stat.fetch(:calls, 0).to_i
          calls.zero? ? nil : stat.fetch(:successes, 0).to_f / calls
        end

        def quota_remaining(id)
          Master::Io::ModelQuota.remaining(id)
        rescue StandardError
          nil
        end

        def quota_state(id)
          return :exhausted if Master::Io::ModelQuota.over_quota?(id)
          return Master::Io::QuotaGate.state if paid_model?(id)

          :available
        rescue StandardError
          :unknown
        end

        def paid_model?(id)
          text = id.to_s
          !text.start_with?("ollama:", "ollama/", "local:", "web-chat:") &&
            !text.end_with?(":free", ":cloud", "-cloud")
        end

        def persist_stats
          plain = @stats.transform_values { |stat| stat.transform_keys(&:to_s) }
          write_atomic(stats_path, YAML.dump(plain), fsync: false, fsync_dir: false, mode: 0o600)
        rescue StandardError => e
          Master::Ground::Swallow.log(e, context: "compute_pool.persist_stats")
        end

        def rolling_average(previous, value, count)
          return value if count <= 1
          previous + ((value - previous) / count)
        end

        def load_rules
          path = File.join(@root, "data", "models.yml")
          Master.load_yaml(path) || {}
        rescue StandardError => e
          Master::Ground::Swallow.log(e, context: "compute_pool.load_rules")
          {}
        end
      end
    end
  end
end