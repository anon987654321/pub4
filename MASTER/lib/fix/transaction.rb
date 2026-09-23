# frozen_string_literal: true

require "digest"
require "fileutils"
require_relative "../io/atomic_write"

module Master
  module Fix
    # Pass-level transaction for /fix.
    #
    # It snapshots only the pass-owned files and records every state MASTER
    # observes while the pass runs. Rollback refuses to overwrite a state it did
    # not observe, which turns concurrent human edits into a visible conflict
    # rather than silently destroying them.
    class Transaction
      Snapshot = Data.define(:path, :exists, :kind, :content, :mode, :link)

      def initialize(root:, paths:, bus: nil)
        @root = File.expand_path(root)
        @paths = Array(paths).map { |path| normalize(path) }.compact.uniq
        @bus = bus
        @seen = Hash.new { |hash, path| hash[path] = [] }
        @snapshots = {}
        @lock = nil
        @active = false
      end

      def begin!
        raise "transaction already active" if @active

        acquire_lock
        @paths.each do |path|
          abs = absolute(path)
          @snapshots[path] = snapshot(abs)
        end
        observe!
        @active = true
        @bus&.publish("fix:transaction_start", paths: @paths)
        self
      rescue StandardError
        release_lock
        raise
      end

      def observe!
        @paths.each do |path|
          abs = absolute(path)
          @seen[path] << fingerprint(abs)
          @seen[path] = @seen[path].uniq.last(8)
        end
        true
      end

      def changed?
        @paths.any? do |path|
          fingerprint(absolute(path)) != @snapshots.fetch(path).then { |snap| fingerprint_snapshot(snap) }
        end
      end

      def commit!
        raise "transaction not active" unless @active

        @bus&.publish("fix:transaction_commit", paths: @paths)
        @active = false
        release_lock
        Result.ok(@paths)
      rescue StandardError => e
        @bus&.publish("fix:transaction_commit_failed", error: e.message)
        Result.err("transaction commit: #{e.message}", category: :infrastructure)
      end

      def rollback!
        raise "transaction not active" unless @active

        conflicts = @paths.reject { |path| @seen[path].include?(fingerprint(absolute(path))) }
        unless conflicts.empty?
          @bus&.publish("fix:transaction_conflict", paths: conflicts)
          @active = false
          release_lock
          return Result.err("rollback refused: concurrent changes in #{conflicts.join(", ")}", category: :policy)
        end

        @paths.each { |path| restore(path, @snapshots.fetch(path)) }
        @bus&.publish("fix:transaction_rollback", paths: @paths)
        @active = false
        release_lock
        Result.ok(@paths)
      rescue StandardError => e
        @bus&.publish("fix:transaction_rollback_failed", error: e.message)
        @active = false
        release_lock
        Result.err("transaction rollback: #{e.message}", category: :infrastructure)
      end

      def active? = @active

      private

      def acquire_lock
        path = File.join(@root, ".master", "fix_transaction.lock")
        FileUtils.mkdir_p(File.dirname(path))
        @lock = File.open(path, File::RDWR | File::CREAT, 0o600)
        @lock.flock(File::LOCK_EX)
      end

      def release_lock
        return unless @lock

        @lock.flock(File::LOCK_UN)
        @lock.close
        @lock = nil
      end

      def normalize(path)
        value = path.to_s
        return if value.empty?

        full = File.expand_path(value, @root)
        root = File.expand_path(@root)
        return unless full == root || full.start_with?(root + File::SEPARATOR)

        full.delete_prefix(root + File::SEPARATOR)
      end

      def absolute(path) = File.join(@root, path)

      def snapshot(path)
        return Snapshot.new(path, false, :missing, nil, nil, nil) unless File.exist?(path) || File.symlink?(path)

        stat = File.lstat(path)
        if stat.symlink?
          Snapshot.new(path, true, :symlink, nil, stat.mode & 0o7777, File.readlink(path))
        elsif stat.file?
          Snapshot.new(path, true, :file, File.binread(path), stat.mode & 0o7777, nil)
        else
          Snapshot.new(path, true, :other, nil, stat.mode & 0o7777, nil)
        end
      end

      def fingerprint(path)
        return "missing" unless File.exist?(path) || File.symlink?(path)

        stat = File.lstat(path)
        return "symlink:#{stat.mode}:#{File.readlink(path)}" if stat.symlink?
        return "other:#{stat.mode}:#{stat.size}" unless stat.file?

        "file:#{Digest::SHA256.hexdigest(File.binread(path))}"
      rescue StandardError => e
        "error:#{e.class}:#{e.message}"
      end

      def fingerprint_snapshot(snapshot)
        return "missing" unless snapshot.exists
        return "symlink:#{snapshot.mode}:#{snapshot.link}" if snapshot.kind == :symlink
        return "other:#{snapshot.mode}" unless snapshot.kind == :file

        "file:#{Digest::SHA256.hexdigest(snapshot.content)}"
      end

      def restore(path, snapshot)
        abs = absolute(path)
        case snapshot.kind
        when :missing
          File.delete(abs) if File.exist?(abs) || File.symlink?(abs)
        when :symlink
          File.delete(abs) if File.exist?(abs) || File.symlink?(abs)
          FileUtils.mkdir_p(File.dirname(abs))
          File.symlink(snapshot.link, abs)
        when :file
          FileUtils.mkdir_p(File.dirname(abs))
          write_atomic(abs, snapshot.content, mode: snapshot.mode)
        end
      end
    end
  end
end
