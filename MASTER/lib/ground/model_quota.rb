# frozen_string_literal: true

require "fileutils"
require "json"
require "time"

module Master
  module Ground
    # Per-model daily request budget for OpenRouter :free slugs (200/day/key typical).
    module ModelQuota
      FREE_RE = /:free\z|\Aopenrouter\//.freeze
      DEFAULT_DAILY = 200

      @mutex = Mutex.new

      module_function

      def daily_limit
        cfg = Master.load_yaml(File.join(Master::ROOT, "data", "models.yml")) || {}
        cfg.dig("openrouter", "daily_quota_per_model").to_i.positive? ?
          cfg.dig("openrouter", "daily_quota_per_model").to_i : DEFAULT_DAILY
      rescue StandardError
        DEFAULT_DAILY
      end

      def trackable?(model) = FREE_RE.match?(model.to_s)

      def record(model)
        return unless trackable?(model)

        @mutex.synchronize do
          data = load_data
          day = today_key
          data[day] ||= {}
          key = model.to_s
          data[day][key] = data[day].fetch(key, 0) + 1
          prune_old_days!(data, day)
          save_data(data)
        end
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "model_quota.record", model: model.to_s)
      end

      def count(model, day: today_key)
        load_data.dig(day, model.to_s).to_i
      rescue StandardError
        0
      end

      def over_quota?(model, day: today_key)
        return false unless trackable?(model)

        count(model, day:) >= daily_limit
      end

      def remaining(model, day: today_key)
        return unless trackable?(model)

        [daily_limit - count(model, day:), 0].max
      end

      def exhausted_models(day: today_key)
        data = load_data[day] || {}
        data.select { |model, used| trackable?(model) && used.to_i >= daily_limit }.keys
      rescue StandardError
        []
      end

      def snapshot(day: today_key)
        data = load_data[day] || {}
        tracked = data.select { |model, _| trackable?(model) }
        {
          day: day,
          limit: daily_limit,
          models: tracked.transform_values(&:to_i),
          exhausted: tracked.select { |_, used| used.to_i >= daily_limit }.keys
        }
      end

      def path
        File.join(Master::ROOT, ".master", "model_quota.json")
      end

      def today_key = Time.now.utc.strftime("%Y-%m-%d")

      def load_data
        return {} unless File.file?(path)
        JSON.parse(File.read(path))
      rescue StandardError
        {}
      end

      def save_data(data)
        FileUtils.mkdir_p(File.dirname(path))
        File.write(path, JSON.pretty_generate(data))
      end

      def prune_old_days!(data, keep_day)
        cutoff = (Date.parse(keep_day) - 7).strftime("%Y-%m-%d")
        data.delete_if { |day, _| day < cutoff }
      end
    end
  end
end
