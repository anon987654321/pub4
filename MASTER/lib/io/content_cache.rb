# frozen_string_literal: true

require "digest"

module Master
  module Io
    # Remembers the SHA-256 of files already hashed, keyed by path, and answers
    # "what is its digest now" from mtime and size when they still match.
    #
    # Git's racy rule keeps that answer honest: a file edited in the same
    # timestamp tick as the hash keeps its mtime and may keep its size, so a row
    # is trusted only when it was hashed more than RACY_NS after the file's
    # mtime. A younger row is re-hashed. `verify: true` re-hashes regardless,
    # for the caller that must catch a deliberate mtime reset.
    #
    # No blob store: reading a stored copy costs what reading the file does, so
    # only the digest is worth keeping.
    class ContentCache
      Row = Data.define(:sha256, :mtime_ns, :size, :hashed_at_ns)
      RACY_NS = 2_000_000_000

      def initialize
        @rows = {}
        @mutex = Mutex.new
      end

      # Digest of a file whose bytes the caller has just hashed itself.
      def record(path, sha256)
        stat = File.stat(path)
        store(path, sha256, stat)
        sha256
      rescue SystemCallError
        nil
      end

      # Current digest of the file, or nil when it is gone.
      def digest(path, verify: false)
        stat = File.stat(path)
        row = @mutex.synchronize { @rows[path] }
        return row.sha256 if !verify && row && trusted?(row, stat)

        store(path, Digest::SHA256.file(path).hexdigest, stat)
      rescue SystemCallError
        nil
      end

      def forget(path) = @mutex.synchronize { @rows.delete(path) }

      def clear = @mutex.synchronize { @rows.clear }

      private

      def trusted?(row, stat)
        row.size == stat.size && row.mtime_ns == mtime_ns(stat) && row.hashed_at_ns - row.mtime_ns > RACY_NS
      end

      def store(path, sha256, stat)
        row = Row.new(sha256:, mtime_ns: mtime_ns(stat), size: stat.size, hashed_at_ns: now_ns)
        @mutex.synchronize { @rows[path] = row }
        sha256
      end

      def mtime_ns(stat) = (stat.mtime.to_r * 1_000_000_000).to_i

      def now_ns = (Time.now.to_r * 1_000_000_000).to_i
    end
  end
end
