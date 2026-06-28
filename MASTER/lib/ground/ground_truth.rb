# frozen_string_literal: true

module Master
  module Ground
    # Enforces rules.yml ground_truth_check — fresh reads before claims/commits.
    class GroundTruth
      Entry = Data.define(:path, :sha256, :read_at)

      def initialize(max_age_seconds: nil, event_bus: nil)
        @max_age = max_age_seconds || load_max_age
        @bus = event_bus
        @reads = {}
        @mutex = Mutex.new
      end

      def record_read!(path, content: nil)
        resolved = File.expand_path(path)
        body = content || File.read(resolved)
        entry = Entry.new(path: resolved, sha256: Digest::SHA256.hexdigest(body), read_at: Time.now.to_f)
        @mutex.synchronize { @reads[resolved] = entry }
        @bus&.publish("ground_truth:read", path: resolved, sha256: entry.sha256)
        entry
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "ground_truth.record_read", path:)
        nil
      end

      def fresh?(path, content: nil)
        resolved = File.expand_path(path)
        entry = @mutex.synchronize { @reads[resolved] }
        return false unless entry
        return false if (Time.now.to_f - entry.read_at) > @max_age

        if content
          Digest::SHA256.hexdigest(content) == entry.sha256
        else
          File.exist?(resolved) && Digest::SHA256.hexdigest(File.read(resolved)) == entry.sha256
        end
      rescue StandardError
        false
      end

      def assert_fresh!(path, reason: "claim_task_complete")
        return Result.ok(path) if fresh?(path)

        @bus&.publish("ground_truth:stale", path:, reason:)
        Result.err("ground_truth: stale read required for #{path} before #{reason}", category: :policy)
      end

      def reset!
        @mutex.synchronize { @reads.clear }
      end

      private

      def load_max_age
        data = Master.load_yaml(Master::RULES_PATH) || {}
        data.dig("ground_truth_check", "cache_max_age_seconds").to_i
      rescue StandardError
        5
      end
    end
  end
end

require "digest"
