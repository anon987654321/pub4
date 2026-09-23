# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "securerandom"
require_relative "../io/atomic_write"

module Master
  module Fix
    # Disk-backed pass transaction for /fix.
    #
    # Snapshots live outside the Ruby heap and carry their own lifecycle marker.
    # An interrupted transaction in the "open" state can therefore be restored
    # on the next invocation; "delivering" means Git delivery may already have
    # started, so recovery preserves the tree and lets /fix re-observe it.
    class Transaction
      Snapshot = Data.define(:path, :exists, :kind, :mode, :link, :store)

      ROOT_DIR = ".master/fix_transactions"
      LOCK = ".master/fix_transaction.lock"
      MANIFEST = "manifest.json"

      def self.recover!(root:, id:, bus: nil)
        transaction = new(root:, paths: [], id:, bus:)
        transaction.recover!
      end

      def initialize(root:, paths:, id: SecureRandom.hex(10), bus: nil)
        @root = File.expand_path(root)
        @paths = Array(paths).map { |path| normalize(path) }.compact.uniq
        @id = id.to_s
        @bus = bus
        @seen = Hash.new { |hash, path| hash[path] = [] }
        @snapshots = {}
        @dir = File.join(@root, ROOT_DIR, @id)
        @lock = nil
        @active = false
        @state = "new"
      end

      def begin!
        raise "transaction already active" if @active
        raise "transaction id is empty" if @id.empty?

        acquire_lock
        FileUtils.mkdir_p(@dir)
        @paths.each { |path| @snapshots[path] = snapshot(path) }
        @state = "open"
        @active = true
        persist!
        observe!
        @bus&.publish("fix:transaction_start", id: @id, paths: @paths)
        self
      rescue StandardError
        release_lock
        raise
      end

      def observe!
        @paths.each do |path|
          @seen[path] << fingerprint(absolute(path))
          @seen[path] = @seen[path].uniq.last(8)
        end
        persist! if @active
        true
      end

      def begin_delivery!
        raise "transaction not active" unless @active
        raise "transaction is not open: #{@state}" unless @state == "open"

        @state = "delivering"
        persist!
        @bus&.publish("fix:transaction_delivery_start", id: @id, paths: @paths)
        true
      end

      def finalize!
        raise "transaction not active" unless @active
        @state = "committed"
        @active = false
        persist!
        cleanup!
        release_lock
        @bus&.publish("fix:transaction_commit", id: @id, paths: @paths)
        Result.ok(@paths)
      rescue StandardError => e
        @bus&.publish("fix:transaction_commit_failed", id: @id, error: e.message)
        @active = false
        release_lock
        Result.err("transaction finalize: #{e.message}", category: :infrastructure)
      end

      def rollback!
        raise "transaction not active" unless @active || persisted?
        return preserve_delivery! if @state == "delivering"

        conflicts = @paths.reject { |path| @seen[path].include?(fingerprint(absolute(path))) }
        unless conflicts.empty?
          @state = "conflict"
          persist!
          @active = false
          release_lock
          @bus&.publish("fix:transaction_conflict", id: @id, paths: conflicts)
          return Result.err("rollback refused: concurrent changes in #{conflicts.join(", ")}", category: :policy)
        end

        @snapshots.each { |path, snap| restore(path, snap) }
        @state = "rolled_back"
        persist!
        cleanup!
        @active = false
        release_lock
        @bus&.publish("fix:transaction_rollback", id: @id, paths: @paths)
        Result.ok(@paths)
      rescue StandardError => e
        @bus&.publish("fix:transaction_rollback_failed", id: @id, error: e.message)
        @active = false
        release_lock
        Result.err("transaction rollback: #{e.message}", category: :infrastructure)
      end

      def recover!
        load_manifest!
        case @state
        when "open"
          @active = true
          result = rollback!
          @bus&.publish("fix:transaction_recovered", id: @id, result: result.to_s)
          result
        when "delivering"
          @bus&.publish("fix:transaction_delivery_recovered", id: @id,
                        reason: "delivery had started; preserve tree and re-observe")
          @active = false
          cleanup!
          Result.ok(:preserved_delivery)
        when "committed", "rolled_back", "conflict"
          cleanup!
          Result.ok(@state.to_sym)
        else
          cleanup!
          Result.err("unknown transaction state: #{@state}", category: :infrastructure)
        end
      rescue StandardError => e
        @bus&.publish("fix:transaction_recovery_failed", id: @id, error: e.message)
        Result.err("transaction recovery: #{e.message}", category: :infrastructure)
      ensure
        release_lock
      end

      def active? = @active
      def id = @id
      def state = @state

      private

      def persisted? = File.file?(File.join(@dir, MANIFEST))

      def acquire_lock
        path = File.join(@root, LOCK)
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
        abs = absolute(path)
        return Snapshot.new(path, false, :missing, nil, nil, nil) unless File.exist?(abs) || File.symlink?(abs)

        stat = File.lstat(abs)
        if stat.symlink?
          Snapshot.new(path, true, :symlink, stat.mode & 0o7777, File.readlink(abs), nil)
        elsif stat.file?
          store = File.join(@dir, "files", encoded(path))
          snapshot_file(abs, store)
          Snapshot.new(path, true, :file, stat.mode & 0o7777, nil, store)
        else
          Snapshot.new(path, true, :other, stat.mode & 0o7777, nil, nil)
        end
      end

      def snapshot_file(source, destination)
        FileUtils.mkdir_p(File.dirname(destination))
        before = fingerprint(source)
        temporary = "#{destination}.tmp.#{Process.pid}.#{SecureRandom.hex(4)}"
        File.open(source, "rb") do |input|
          File.open(temporary, "wb", 0o600) do |output|
            IO.copy_stream(input, output)
            output.flush
            output.fsync
          end
        end
        raise "source changed during snapshot: #{source}" unless before == fingerprint(source)
        File.rename(temporary, destination)
      ensure
        File.delete(temporary) if defined?(temporary) && temporary && File.exist?(temporary)
      end

      def fingerprint(path)
        return "missing" unless File.exist?(path) || File.symlink?(path)

        stat = File.lstat(path)
        return "symlink:#{stat.mode}:#{File.readlink(path)}" if stat.symlink?
        return "other:#{stat.mode}:#{stat.size}" unless stat.file?

        "file:#{Digest::SHA256.file(path)}"
      rescue StandardError => e
        "error:#{e.class}:#{e.message}"
      end

      def persist!
        manifest = {
          "version" => 1,
          "id" => @id,
          "state" => @state,
          "paths" => @paths,
          "seen" => @seen,
          "snapshots" => @snapshots.transform_values(&:to_h),
        }
        write_atomic(File.join(@dir, MANIFEST), JSON.pretty_generate(manifest) + "
", mode: 0o600)
      end

      def load_manifest!
        path = File.join(@dir, MANIFEST)
        raise "transaction manifest not found: #{@id}" unless File.file?(path)

        data = JSON.parse(File.read(path, encoding: "UTF-8"))
        raise "transaction manifest version unsupported" unless data["version"].to_i == 1
        raise "transaction manifest malformed" unless data["snapshots"].is_a?(Hash)

        @state = data.fetch("state")
        @paths = Array(data["paths"])
        @seen = Hash.new { |hash, key| hash[key] = [] }
        data.fetch("seen", {}).each { |key, values| @seen[key] = Array(values) }
        @snapshots = data["snapshots"].to_h.transform_values do |raw|
          Snapshot.new(
            raw["path"], raw["exists"], raw["kind"].to_sym, raw["mode"], raw["link"], raw["store"],
          )
        end
        true
      rescue JSON::ParserError => e
        raise "transaction manifest is corrupt: #{e.message}"
      end

      def restore(path, snapshot)
        abs = absolute(path)
        case snapshot.kind
        when :missing
          remove(abs)
        when :symlink
          remove(abs)
          FileUtils.mkdir_p(File.dirname(abs))
          File.symlink(snapshot.link, abs)
        when :file
          FileUtils.mkdir_p(File.dirname(abs))
          content = File.binread(snapshot.store)
          write_atomic(abs, content, mode: snapshot.mode)
        when :other
          raise "cannot restore unsupported path type: #{path}"
        end
      end

      def remove(path)
        File.delete(path) if File.exist?(path) || File.symlink?(path)
      end

      def cleanup!
        FileUtils.rm_rf(@dir)
        parent = File.dirname(@dir)
        FileUtils.rmdir(parent) if Dir.exist?(parent) && Dir.empty?(parent)
      rescue SystemCallError
        nil
      end

      def preserve_delivery!
        @active = false
        release_lock
        Result.ok(:preserved_delivery)
      end

      def encoded(path) = Digest::SHA256.hexdigest(path)[0, 24]
    end
  end
end
