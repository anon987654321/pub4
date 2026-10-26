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
          limit = Integer(max_bytes)
          raise ArgumentError, "trajectory log limit must be positive" unless limit.positive?

          directory = File.dirname(path)
          raise ArgumentError, "trajectory log directory is a symlink" if File.symlink?(directory)
          FileUtils.mkdir_p(directory, mode: 0o700)
          directory_stat = File.lstat(directory)
          raise ArgumentError, "trajectory log directory is not a real directory" unless
            directory_stat.directory? && !directory_stat.symlink?
          File.chmod(0o700, directory)

          line = JSON.generate(@data) + "\n"
          raise ArgumentError, "trajectory record exceeds #{limit}-byte log limit" if line.bytesize > limit

          # Rotation and append must share a process-wide lock: locking only the
          # data file is insufficient after rotation because its inode changes.
          lock_path = "#{path}.lock"
          raise ArgumentError, "trajectory log lock is a symlink" if File.symlink?(lock_path)
          File.open(lock_path, File::RDWR | File::CREAT, 0o600) do |lock|
            File.chmod(0o600, lock_path)
            lock.flock(File::LOCK_EX)

            raise ArgumentError, "trajectory log path is a symlink" if File.symlink?(path)
            if File.exist?(path)
              path_stat = File.lstat(path)
              raise ArgumentError, "trajectory log path is not a regular file" unless path_stat.file? && !path_stat.symlink?

              File.chmod(0o600, path)
            end

            # Reserve room for the new record before appending, so one large record
            # cannot push the active log past its declared cap.
            Master::Trace::Log.rotate(path, [limit - line.bytesize, 0].max, keep_bytes: limit)
            File.open(path, File::WRONLY | File::CREAT | File::APPEND, 0o600) do |io|
              io.write(line)
              io.flush
              io.fsync
            end
          ensure
            lock.flock(File::LOCK_UN) if lock
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
