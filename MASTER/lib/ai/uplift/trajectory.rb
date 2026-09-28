# frozen_string_literal: true

require "json"
require "fileutils"
require "time"

module Master
  module AI
    module Uplift
      class Trajectory
        SCHEMA = "master.llm.trajectory/v1"
        REQUIRED = %w[task model events outcome verified].freeze

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
          raise ArgumentError, "trajectory missing: #{missing.join(", ")}" unless missing.empty?
          raise ArgumentError, "trajectory task is empty" if @data["task"].empty?
          raise ArgumentError, "trajectory events are empty" if @data["events"].empty?
        end

        def score = Benchmark.score(@data)

        def append!(path)
          FileUtils.mkdir_p(File.dirname(path))
          File.open(path, "a") do |io|
            io.flock(File::LOCK_EX)
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
