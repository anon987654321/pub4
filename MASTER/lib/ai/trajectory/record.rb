# frozen_string_literal: true

require "json"
require "fileutils"
require "time"
require_relative "../../trace/log"

module Master
  module AI
    module Trajectory
      class Record
        SCHEMA = "master.llm.trajectory/v1"
        REQUIRED = %w[task model events outcome verified].freeze
        MAX_BYTES = Master::Trace::Log::Event::MAX_BYTES

        attr_reader :data

        def initialize(data)
          @data = normalize(data)
          validate!
        end

        def normalize(value)
          hash = value.is_a?(Hash) ? value.dup : {}
          hash["schema"] = SCHEMA
          hash["task"] = hash.fetch("task", "").to_s
          hash["model"] = hash.fetch("model", "").to_s
          hash["events"] = Array(hash["events"]).map { |event| event.is_a?(Hash) ? stringify(event) : { "event" => event.to_s } }
          hash["outcome"] = hash.fetch("outcome", "unknown").to_s
          hash["verified"] = hash.fetch("verified", false) == true
          hash["recorded_at"] ||= Time.now.utc.iso8601
          hash
        end

        def validate!
          missing = REQUIRED.reject { |key| @data.key?(key) }
          raise ArgumentError, "trajectory record missing: #{missing.join(", ")}" unless missing.empty?
          raise ArgumentError, "trajectory task is empty" if @data["task"].empty?
          raise ArgumentError, "trajectory events are empty" if @data["events"].empty?
        end

        def score = Benchmark.score(@data)

        def append!(path, max_bytes: MAX_BYTES)
          raise ArgumentError, "trajectory log limit must be positive" unless max_bytes.to_i.positive?

          FileUtils.mkdir_p(File.dirname(path), mode: 0o700)
          raise ArgumentError, "trajectory log path is a symlink" if File.symlink?(path)
          File.chmod(0o600, path) if File.file?(path)
          Master::Trace::Log.rotate(path, max_bytes)

          File.open(path, File::WRONLY | File::CREAT | File::APPEND, 0o600) do |io|
            io.flock(File::LOCK_EX)
            io.chmod(0o600)
            io.puts(JSON.generate(@data))
            io.flush
            io.flock(File::LOCK_UN)
          end
          self
        end

        private

        def stringify(hash)
          hash.each_with_object({}) do |(key, value), out|
            out[key.to_s] = value.is_a?(Hash) ? stringify(value) : value
          end
        end
      end
    end
  end
end
