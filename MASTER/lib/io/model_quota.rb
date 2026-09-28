# frozen_string_literal: true

require "date"
require "fileutils"
require "json"
require "time"
require_relative "atomic_write"

module Master
  module Io
    # Per-model daily request budget for OpenRouter :free slugs (200/day/key typical).
    # One of three quota objects, each answering a different question: this one
    # counts calls per free model per day; QuotaGate says whether a paid
    # provider still has credit (test/test_quota_gate.rb); ModelSkipCache
    # parks a model that just failed (test/test_model_skip_cache.rb).
    module ModelQuota
      extend self
      include Master::Io::AtomicWrite
      FREE_RE = /:free\z|\Aopenrouter\//.freeze
      DEFAULT_DAILY = 200

      @mutex = Mutex.new

      module_function

      def daily_limit
        cfg = Master.load_yaml(File.join(Master::ROOT, "data", "models.yml"))
        value = cfg&.dig("openrouter", "daily_quota_per_model")
        value.to_i.positive? ? value.to_i : DEFAULT_DAILY
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "model_quota.daily_limit", severity: :load_bearing)
        raise "model quota policy unreadable: #{e.class}: #{e.message}"
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
        raise "model quota accounting failed: #{e.class}: #{e.message}"
      end

      def count(model, day: today_key)
        load_data.dig(day, model.to_s).to_i
      end

      def over_quota?(model, day: today_key)
        return false unless trackable?(model)

        count(model, day:) >= daily_limit
      end

      def remaining(model, day: today_key)
        return unless trackable?(model)

        [daily_limit - count(model, day:), 0].max
      end

      def burn_rate_per_day(model, day: today_key, now: Time.now.utc)
        used = count(model, day:)
        start = Time.utc(*Date.strptime(day, "%Y-%m-%d").year_month_day)
        elapsed = [now.to_f - start.to_f, 300.0].max
        return 0.0 if used.zero?

        used.to_f * 86_400 / elapsed
      rescue ArgumentError
        0.0
      end

      def forecast(model, day: today_key, now: Time.now.utc)
        return unless trackable?(model)

        used = count(model, day:)
        limit = daily_limit
        remaining = [limit - used, 0].max
        projected_daily = burn_rate_per_day(model, day:, now:)
        exhaustion_hours =
          if remaining.zero?
            0.0
          elsif projected_daily.positive?
            remaining.to_f / (projected_daily / 24.0)
          end

        {
          model: model.to_s,
          day:,
          used:,
          limit:,
          remaining:,
          projected_daily: projected_daily.round(2),
          exhaustion_hours: exhaustion_hours&.round(2),
        }
      end

      def burn_risk?(model, threshold: 0.8, day: today_key, now: Time.now.utc)
        forecasted = forecast(model, day:, now:)
        return false unless forecasted

        forecasted[:projected_daily] >= forecasted[:limit] * threshold
      end

      def exhausted_models(day: today_key)
        data = load_data[day] || {}
        data.select { |model, used| trackable?(model) && used.to_i >= daily_limit }.keys
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "ModelQuota.exhausted_models")
        raise "model quota state unreadable: #{e.class}: #{e.message}"
      end

      def snapshot(day: today_key)
        data = load_data[day] || {}
        tracked = data.select { |model, _| trackable?(model) }
        {
          day:,
          limit: daily_limit,
          models: tracked.transform_values(&:to_i),
          exhausted: tracked.select { |_, used| used.to_i >= daily_limit }.keys,
          forecasts: tracked.keys.to_h { |model| [model, forecast(model, day:)] },
        }
      end

      def path
        File.join(Master::ROOT, ".master", "model_quota.json")
      end

      def today_key = Time.now.utc.strftime("%Y-%m-%d")

      def load_data
        return {} unless File.file?(path)
        JSON.parse(File.read(path))
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "ModelQuota.load_data")
        raise "model quota state unreadable: #{e.class}: #{e.message}"
      end

      def save_data(data)
        FileUtils.mkdir_p(File.dirname(path))
        write_atomic(path, JSON.pretty_generate(data) + "\n", fsync: false, fsync_dir: false, mode: 0o600)
      end

      def prune_old_days!(data, keep_day)
        cutoff = (Date.parse(keep_day) - 7).strftime("%Y-%m-%d")
        data.delete_if { |day, _| day < cutoff }
      end
    end
  end
end
