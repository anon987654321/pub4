# frozen_string_literal: true

require "date"
require "fileutils"
require "json"
require "time"
require_relative "atomic_write"

module Master
  module Io
    # Per-model daily request budget for OpenRouter :free slugs; config is authoritative.
    # One of three quota objects, each answering a different question: this one
    # counts calls per free model per day; QuotaCheck says whether a paid
    # provider still has credit (test/test_quota_check.rb); ModelSkipCache
    # parks a model that just failed (test/test_model_skip_cache.rb).
    module ModelQuota
      extend self
      include ::Master::Io::AtomicWrite
      FREE_RE = /:free\z/.freeze
      DEFAULT_DAILY = 50

      @mutex = Mutex.new

      module_function

      def daily_limit
        cfg = Master.models_config
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
          with_state_lock do
            data = load_data
            day = today_key
            data[day] ||= {}
            key = model.to_s
            data[day][key] = data[day].fetch(key, 0) + 1
            prune_old_days!(data, day)
            save_data(data)
          end
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

      def burn_rate_per_day(model, now: Time.now.utc, day: now.utc.strftime("%Y-%m-%d"))
        used = count(model, day:)
        date = Date.strptime(day, "%Y-%m-%d")
        start = Time.utc(date.year, date.month, date.day)
        elapsed = [now.to_f - start.to_f, 300.0].max
        return 0.0 if used.zero?

        used.to_f * 86_400 / elapsed
      rescue ArgumentError
        0.0
      end

      def forecast(model, now: Time.now.utc, day: now.utc.strftime("%Y-%m-%d"))
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

      # Process-local Mutex protects threads; the sidecar flock protects the
      # read-modify-write transaction across independent MASTER processes.
      def with_state_lock
        destination = File.expand_path(path)
        directory = File.dirname(destination)
        raise IOError, "refusing symlinked model quota directory" if File.symlink?(directory)

        FileUtils.mkdir_p(directory, mode: 0o700)
        directory_stat = File.lstat(directory)
        unless directory_stat.directory? && !directory_stat.symlink? && (directory_stat.mode & 0o002).zero?
          raise IOError, "model quota directory must be a real, non-world-writable directory"
        end

        lock_path = "#{destination}.lock"
        raise IOError, "refusing symlinked model quota lock" if File.symlink?(lock_path)
        flags = File::RDWR | File::CREAT
        flags |= File::NOFOLLOW if File.const_defined?(:NOFOLLOW)
        File.open(lock_path, flags, 0o600) do |file|
          opened = file.stat
          unless opened.file? && opened.nlink == 1 && (opened.mode & 0o077).zero?
            raise IOError, "model quota lock must be a private singly linked regular file"
          end

          current = File.lstat(lock_path)
          unless current.file? && !current.symlink? && current.nlink == 1 &&
                 current.dev == opened.dev && current.ino == opened.ino
            raise IOError, "model quota lock path changed while opening"
          end
          raise IOError, "could not acquire model quota lock" unless file.flock(File::LOCK_EX)

          begin
            current = File.lstat(lock_path)
            unless current.file? && !current.symlink? && current.nlink == 1 &&
                   current.dev == opened.dev && current.ino == opened.ino
              raise IOError, "model quota lock path changed while waiting for its lock"
            end
            yield
          ensure
            file.flock(File::LOCK_UN)
          end
        end
      rescue SystemCallError => e
        raise IOError, "cannot safely lock model quota state: #{e.class}: #{e.message}"
      end

      def path
        ENV["MASTER_MODEL_QUOTA_PATH"] || File.join(Master::ROOT, ".master", "model_quota.json")
      end

      def today_key = Time.now.utc.strftime("%Y-%m-%d")

      def load_data
        state_path = File.expand_path(path)
        directory = File.dirname(state_path)
        return {} unless File.exist?(directory) || File.symlink?(directory)

        directory_stat = File.lstat(directory)
        unless directory_stat.directory? && !directory_stat.symlink? && (directory_stat.mode & 0o002).zero?
          raise IOError, "model quota directory must be a real, non-world-writable directory"
        end
        return {} unless File.exist?(state_path) || File.symlink?(state_path)

        before = File.lstat(state_path)
        unless before.file? && !before.symlink? && before.nlink == 1
          raise IOError, "model quota state must be a singly linked regular file"
        end
        if (before.mode & 0o077).positive?
          raise IOError, "model quota state permissions must be private (0600 or stricter)"
        end

        flags = File::RDONLY
        flags |= File::NOFOLLOW if File.const_defined?(:NOFOLLOW)
        File.open(state_path, flags) do |file|
          opened = file.stat
          current = File.lstat(state_path)
          unless current.file? && !current.symlink? && current.nlink == 1 &&
                 current.dev == opened.dev && current.ino == opened.ino
            raise IOError, "model quota state path changed while opening"
          end

          raw = file.read
          after = File.lstat(state_path)
          unless after.file? && !after.symlink? && after.nlink == 1 &&
                 after.dev == opened.dev && after.ino == opened.ino &&
                 after.size == opened.size && after.mtime == opened.mtime && after.ctime == opened.ctime
            raise IOError, "model quota state changed while reading"
          end
          JSON.parse(raw)
        end
      rescue Errno::EACCES => e
        # The daemon writes this file owner-only, and a deploy boot check may run
        # as another user. That diagnostic reader cannot enforce the daemon's
        # quota, so preserve the documented empty-view behavior for EACCES only.
        Master::Ground::Swallow.log(e, context: "ModelQuota.load_data")
        {}
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
