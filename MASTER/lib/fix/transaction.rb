# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "securerandom"
require_relative "../io/atomic_write"
require_relative "transaction/delivery"
require_relative "transaction/recovery"

module Master
  module Fix
    # Disk-backed pass transaction for /fix.
    #
    # Snapshots live outside the Ruby heap and carry their own lifecycle marker.
    # An interrupted transaction in the "open" state can therefore be restored
    # on the next invocation; "delivering" means Git delivery may already have
    # started, so recovery preserves the tree and lets /fix re-observe it.
    class Transaction
      include Master::Io::AtomicWrite

      Snapshot = Data.define(:path, :exists, :kind, :mode, :link, :store)

      ROOT_DIR = ".master/fix_transactions"
      LOCK = ".master/fix_transaction.lock"
      MANIFEST = "manifest.json"

      def self.normalize_id(id)
        value = id.to_s
        raise ArgumentError, "transaction id is unsafe" unless value.match?(%r{\A[a-zA-Z0-9_-]+\z})

        value
      end
      private_class_method :normalize_id

      def initialize(root:, paths:, id: SecureRandom.hex(10), bus: nil)
        @root = File.expand_path(root)
        @paths = Array(paths).map { |path| normalize(path) }.compact.uniq
        @id = self.class.send(:normalize_id, id)
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
        observe!
        emit("fix:transaction_start", id: @id, paths: @paths)
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

      # The delivery sub-machine (begin_delivery! / record_commit! /
      # delivery_pending? / delivery_head_after / finalize_delivery!) lives in
      # Delivery, reached through this one accessor, so those five methods no
      # longer count against Transaction's own surface. Delivery is a thin
      # wrapper around this instance, not a second copy of its state: it reads
      # and writes the same @state/@delivery_head_* ivars and calls the same
      # private persist!/emit this class already had, so the persisted
      # manifest format and every emitted event name are unchanged.
      def delivery
        @delivery ||= Delivery.new(self)
      end

      def finalize!
        raise "transaction not active" unless @active
        @state = "committed"
        @active = false
        persist!
        cleanup!
        release_lock
        emit("fix:transaction_commit", id: @id, paths: @paths)
        Result.ok(@paths)
      rescue StandardError => e
        emit("fix:transaction_commit_failed", id: @id, error: e.message)
        @active = false
        release_lock
        Result.err("transaction finalize: #{e.message}", category: :infrastructure)
      end

      def rollback!
        raise "transaction not active" unless @active || persisted?
        return delivery.preserve! if @state == "delivering" && delivery.pending?
        @state = "open" if @state == "delivering"
        @delivery_head_before = nil if @state == "open"

        conflicts = conflicts()
        return reject_rollback_conflict(conflicts) unless conflicts.empty?

        restore_snapshots_and_roll_back
      rescue StandardError => e
        emit("fix:transaction_rollback_failed", id: @id, error: e.message)
        @active = false
        release_lock
        Result.err("transaction rollback: #{e.message}", category: :infrastructure)
      end

      def conflicts
        @paths.reject { |path| @seen[path].include?(fingerprint(absolute(path))) }
      end

      def id = @id
      def state = @state
      def active? = @active

      private

      def reject_rollback_conflict(conflicts)
        @state = "conflict"
        persist!
        @active = false
        release_lock
        emit("fix:transaction_conflict", id: @id, paths: conflicts)
        Result.err("rollback refused: concurrent changes in #{conflicts.join(", ")}", category: :policy)
      end

      def restore_snapshots_and_roll_back
        @snapshots.each { |path, snap| restore(path, snap) }
        @state = "rolled_back"
        persist!
        cleanup!
        @active = false
        release_lock
        emit("fix:transaction_rollback", id: @id, paths: @paths)
        Result.ok(@paths)
      end

      # Reached only via Recovery.recover! (load_persisted(...).send(:recover!))
      # -- nothing else calls an instance's own recover! directly, confirmed
      # by grepping every lib/ and test/ caller before making this private.
      def recover!
        load_manifest!
        recover_for_state
      rescue StandardError => e
        emit("fix:transaction_recovery_failed", id: @id, error: e.message)
        Result.err("transaction recovery: #{e.message}", category: :infrastructure)
      ensure
        release_lock
      end

      def recover_for_state
        case @state
        when "open" then recover_open_state
        when "delivering" then delivery.send(:recover!)
        when "committed", "rolled_back" then recover_terminal_state
        when "conflict" then recover_error_state("transaction recovery found a concurrent edit", :policy)
        else recover_error_state("unknown transaction state: #{@state}", :infrastructure)
        end
      end

      # cleanup! is called for its side effect (remove the transaction
      # directory); its own return value is not the Result -- the original
      # code called it and returned Result separately on the next line, and
      # `cleanup! && Result...` would have made the Result conditional on
      # cleanup!'s return, which is nil whenever its own `if` guard is false.
      def recover_terminal_state
        cleanup!
        Result.ok(@state.to_sym)
      end

      def recover_error_state(message, category)
        cleanup!
        Result.err(message, category:)
      end

      def recover_open_state
        @active = true
        result = rollback!
        emit("fix:transaction_recovered", id: @id, result: result.to_s)
        result
      end

      def emit(event, **payload)
        @bus&.publish(event, **payload)
      rescue StandardError => e
        warn("trace0: #{e.class}: #{e.message}") if ENV["MASTER_TRACE_STRICT"] == "1"
        nil
      end

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
          "delivery_head_before" => @delivery_head_before,
          "delivery_head_after" => @delivery_head_after,
          "paths" => @paths,
          "seen" => @seen,
          "snapshots" => @snapshots.transform_values(&:to_h),
        }
        write_atomic(File.join(@dir, MANIFEST), JSON.pretty_generate(manifest) + "\n", mode: 0o600)
      end

      def load_manifest!
        path = File.join(@dir, MANIFEST)
        raise "transaction manifest not found: #{@id}" unless File.file?(path)

        data = JSON.parse(File.read(path, encoding: "UTF-8"))
        raise "transaction manifest version unsupported" unless data["version"].to_i == 1
        raise "transaction manifest malformed" unless data["snapshots"].is_a?(Hash)

        @state = data.fetch("state")
        @delivery_head_before = data["delivery_head_before"]
        @delivery_head_after = data["delivery_head_after"]
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

      def encoded(path) = Digest::SHA256.hexdigest(path)[0, 24]
    end
  end
end
