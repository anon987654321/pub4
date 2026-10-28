# frozen_string_literal: true

require "digest"

module Master
  module Ground
    # Fresh reads before claims/commits. laws.yml carries no ground_truth_check
    # key, so the age window is the constant below unless the caller passes one.
    class Truth
      Entry = Data.define(:path, :sha256, :read_at)
      DEFAULT_MAX_AGE_SECONDS = 300

      def initialize(max_age_seconds: nil, event_bus: nil)
        @max_age = max_age_seconds || DEFAULT_MAX_AGE_SECONDS
        @bus = event_bus
        @reads = {}
        @contents = Io::ContentCache.new
        @mutex = Mutex.new
      end

      def record_read!(path, content: nil)
        resolved = File.expand_path(path)
        body = content || File.read(resolved)
        entry = Entry.new(path: resolved, sha256: Digest::SHA256.hexdigest(body), read_at: Time.now.to_f)
        @mutex.synchronize { @reads[resolved] = entry }
        @contents.record(resolved, entry.sha256)
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
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "Truth.fresh?")
        false
      end

      # A file this session recorded and whose bytes have not changed since: /fix's own write,
      # and no one else's save after it.
      def recorded_unchanged?(path)
        resolved = File.expand_path(path)
        @mutex.synchronize { @reads.key?(resolved) } && !changed_since_read?(resolved)
      end

      # True only for a file this session read whose bytes differ now. No age
      # limit, unlike fresh?: a read an hour old is still the version a whole
      # overwrite was composed against. A file never read answers false.
      def changed_since_read?(path)
        resolved = File.expand_path(path)
        entry = @mutex.synchronize { @reads[resolved] }
        return false unless entry
        return true unless File.exist?(resolved)

        @contents.digest(resolved) != entry.sha256
      end

      def assert_fresh!(path, reason: "claim_task_complete")
        return Result.ok(path) if fresh?(path)

        @bus&.publish("ground_truth:stale", path:, reason:)
        Result.err("ground_truth: stale read required for #{path} before #{reason}", category: :policy)
      end

      def reset!
        @mutex.synchronize { @reads.clear }
        @contents.clear
      end
    end
  end
end
