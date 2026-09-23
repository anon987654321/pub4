# frozen_string_literal: true

require "fileutils"
require "json"
require "time"
require_relative "../io/atomic_write"

module Master
  module Ground
    # Persisted restart discipline for optional runtime services.
    # A service may recover automatically, but repeated failures become a
    # measured degraded state instead of an unbounded restart storm.
    class ServiceSupervisor
      PATH = ".master/services.json"
      LOCK = ".master/services.lock"
      VERSION = 1

      def initialize(root:, bus: nil, clock: Process::CLOCK_MONOTONIC)
        @root = root
        @bus = bus
        @clock = clock
      end

      def ensure(name:, start:, healthy:, max_restarts: 3, window_seconds: 300, wait_seconds: 10)
        with_lock do
          state = load
          if healthy.call
            reset_after_recovery(state, name)
            return healthy_status(name)
          end

          entry = state["services"][name.to_s] ||= {}
          prune_attempts(entry, window_seconds)

          if Array(entry["attempts"]).size >= max_restarts
            return degraded(name, "restart budget exhausted", entry)
          end

          entry["attempts"] << Time.now.utc.to_f
          entry["last_start_at"] = Time.now.utc.iso8601
          persist(state)

          @bus&.publish("service:restart", service: name, attempt: entry["attempts"].size)
          start.call
          deadline = Process.clock_gettime(@clock) + wait_seconds
          until Process.clock_gettime(@clock) >= deadline
            return healthy_status(name) if healthy.call
            sleep 0.1
          end

          degraded(name, "service did not become healthy after #{wait_seconds}s", entry)
        end
      rescue StandardError => e
        @bus&.publish("service:failure", service: name, error: e.message)
        Result.err("service #{name}: #{e.message}", category: :infrastructure)
      end

      def state(name)
        load["services"][name.to_s] || {}
      end

      private

      def healthy_status(name)
        @bus&.publish("service:healthy", service: name)
        Result.ok(Reliability::Status.healthy("#{name} healthy"))
      end

      def degraded(name, message, entry)
        @bus&.publish("service:degraded", service: name, reason: message,
                      attempts: Array(entry["attempts"]).size)
        Result.ok(Reliability::Status.degraded(message, code: :service_unhealthy,
                                               details: { service: name, attempts: entry["attempts"] }))
      end

      def reset_after_recovery(state, name)
        entry = state["services"][name.to_s]
        return unless entry && Array(entry["attempts"]).any?

        entry["attempts"] = []
        entry["last_healthy_at"] = Time.now.utc.iso8601
        persist(state)
      end

      def prune_attempts(entry, window_seconds)
        cutoff = Time.now.utc.to_f - window_seconds.to_f
        entry["attempts"] = Array(entry["attempts"]).select { |at| at.to_f >= cutoff }
      end

      def load
        path = File.join(@root, PATH)
        return { "version" => VERSION, "services" => {} } unless File.file?(path)

        data = JSON.parse(File.read(path, encoding: "UTF-8"))
        raise "service journal version #{data["version"]} unsupported" unless data["version"].to_i == VERSION
        raise "service journal is malformed" unless data["services"].is_a?(Hash)

        data
      rescue JSON::ParserError => e
        raise "service journal is corrupt: #{e.message}"
      end

      def persist(data)
        path = File.join(@root, PATH)
        FileUtils.mkdir_p(File.dirname(path))
        write_atomic(path, JSON.pretty_generate(data) + "\n", mode: 0o600)
      end

      def with_lock
        path = File.join(@root, LOCK)
        FileUtils.mkdir_p(File.dirname(path))
        File.open(path, File::RDWR | File::CREAT, 0o600) do |io|
          io.flock(File::LOCK_EX)
          yield
        ensure
          io&.flock(File::LOCK_UN)
        end
      end
    end
  end
end
