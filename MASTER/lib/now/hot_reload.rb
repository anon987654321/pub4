# frozen_string_literal: true

module Master
  module Now
  # Watches data/ for mtime changes; republishes config:reloaded events.
  # Polled — no inotify dependency on OpenBSD base.
    class HotReload
      # seconds
      DEFAULT_INTERVAL = 5

      def initialize(data_dir:, event_bus:, interval: DEFAULT_INTERVAL)
        @data_dir = data_dir
        @bus = event_bus
        @interval = interval
        @mtimes = {}
        snapshot
      end

      def start
        @thread = Thread.new do
          loop do
            sleep @interval
            check_once
          rescue StandardError => e
            @bus&.publish("hot_reload:error", error: e.message)
          end
        end
      end

      def stop
        @thread&.kill
      end

      def check_once
        Dir.glob(File.join(@data_dir, "*.yml")).each do |path|
          current = File.mtime(path)
          previous = @mtimes[path]
          next if previous && previous >= current
          @mtimes[path] = current
          @bus&.publish("config:reloaded", file: File.basename(path)) if previous
        end
      end

      private

      def snapshot
        Dir.glob(File.join(@data_dir, "*.yml")).each { |p| @mtimes[p] = File.mtime(p) }
      end
    end
  end
end
