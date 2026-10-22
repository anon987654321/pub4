# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "pathname"
require "securerandom"
require "set"
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
      include ::Master::Io::AtomicWrite

      Snapshot = Data.define(:path, :exists, :kind, :mode, :link, :store)

      ROOT_DIR = ".master/fix_transactions"
      LOCK = ".master/fix_transaction.lock"
      MANIFEST = "manifest.json"
      VALID_STATES = %w[open delivering committed rolled_back conflict].freeze

      def self.normalize_id(id)
        value = id.to_s
        raise ArgumentError, "transaction id is unsafe" unless value.match?(%r{\A[a-zA-Z0-9_-]+\z})

        value
      end
      private_class_method :normalize_id

      def initialize(root:, paths:, id: SecureRandom.hex(10), bus: nil)
        @root = File.expand_path(root)
        @paths = Array(paths).filter_map { |path| normalize(path) }.uniq
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

        created_dir = false
        acquire_lock
        raise "transaction id already exists: #{@id}" if File.exist?(@dir) || File.symlink?(@dir)

        Dir.mkdir(@dir, 0o700)
        created_dir = true
        snapshot_started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        @paths.each do |path|
          captured = snapshot(path)
          raise "transaction cannot safely track unsupported filesystem object: #{path}" if captured.kind == :other

          @snapshots[path] = captured
        end
        @state = "open"
        @active = true
        observe!(verify_snapshot: true)
        emit(
          "fix:transaction_snapshot_summary",
          id: @id,
          tracked_paths: @paths.size,
          file_snapshots: @snapshots.values.count { |item| item.kind == :file },
          elapsed_ms: ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - snapshot_started) * 1000).round,
        )
        emit("fix:transaction_start", id: @id, paths: @paths)
        self
      rescue StandardError
        # begin! can fail after observe! has persisted a usable manifest. The
        # Ruby object must no longer claim an active transaction after releasing
        # the lock, while the durable state remains intact for next-run recovery.
        @active = false
        if persisted?
          release_lock
        else
          cleanup! if created_dir
          release_lock
        end
        raise
      end

      def observe!(verify_snapshot: false)
        @paths.each do |path|
          current = fingerprint(absolute(path))
          if verify_snapshot && !snapshot_matches_fingerprint?(path, @snapshots.fetch(path), current)
            raise "transaction source changed during initial snapshot: #{path}"
          end

          @seen[path] << current
          @seen[path] = @seen[path].uniq.last(8)
        end
        persist! if @active
        true
      end

      # Add a narrowly approved related artifact to this transaction before
      # its first write, so rollback and interrupted-run recovery keep its bytes.
      def enlist!(paths)
        raise "transaction not active" unless @active

        raw = Array(paths)
        selected = raw.map { |path| normalize(path) }
        raise "transaction enlistment contains an unsafe path" if selected.any?(&:nil?)

        added = selected.uniq - @paths
        staged = {}
        added.each { |path| staged[path] = snapshot(path, versioned: true) }
        unsupported = staged.select { |_path, item| item.kind == :other }.keys
        unless unsupported.empty?
          discard_snapshots!(staged.values)
          return Result.err(
            "transaction cannot safely enlist unsupported filesystem object(s): #{unsupported.join(", ")}",
            category: :policy,
          )
        end

        old_paths = @paths
        old_snapshots = @snapshots
        old_seen = @seen
        new_paths = (@paths + added).uniq
        new_snapshots = @snapshots.merge(staged)
        new_seen = duplicate_seen
        added.each do |path|
          current = fingerprint(absolute(path))
          unless snapshot_matches_fingerprint?(path, staged.fetch(path), current)
            discard_snapshots!(staged.values)
            return Result.err("transaction source changed during enlistment: #{path}", category: :policy)
          end
          new_seen[path] = [current]
        end

        @paths = new_paths
        @snapshots = new_snapshots
        @seen = new_seen
        begin
          persist!
        rescue StandardError
          unless persisted_state_matches?(state: @state, paths: new_paths, snapshots: new_snapshots)
            @paths = old_paths
            @snapshots = old_snapshots
            @seen = old_seen
            discard_snapshots!(staged.values)
          end
          raise
        end

        emit("fix:transaction_paths_observed", id: @id, paths: added) unless added.empty?
        emit("fix:transaction_paths_enlisted", id: @id, paths: added)
        Result.ok(added)
      rescue StandardError => e
        emit("fix:transaction_enlist_failed", id: @id, error: e.message)
        Result.err("transaction enlistment: #{e.message}", category: :infrastructure)
      end

      # Refresh only explicitly enlisted paths after the transaction's own
      # verified write. Unrelated files retain their original concurrency guard.
      def observe_paths!(paths)
        raise "transaction not active" unless @active

        selected = Array(paths).map { |path| normalize(path) }
        raise "observation includes an unsafe path" if selected.any?(&:nil?)
        selected = selected.uniq
        raise "observation includes a path outside the transaction" unless (selected - @paths).empty?

        selected.each do |path|
          @seen[path] << fingerprint(absolute(path))
          @seen[path] = @seen[path].uniq.last(8)
        end
        persist!
        emit("fix:transaction_paths_observed", id: @id, paths: selected)
        Result.ok(selected)
      rescue StandardError => e
        emit("fix:transaction_observe_failed", id: @id, error: e.message)
        Result.err("transaction observation: #{e.message}", category: :infrastructure)
      end

      def observed_current?(path)
        relative = normalize(path)
        return false unless relative && @paths.include?(relative)

        expected = @seen[relative].last
        expected && expected == fingerprint(absolute(relative))
      rescue StandardError
        false
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

      # Move the rollback floor after a commit has been pushed. The logical
      # pass transaction stays alive, but an interruption can no longer roll a
      # previously delivered checkpoint back to the pass-start snapshot.
      def checkpoint!(paths)
        raise "transaction not active" unless @active

        selected = Array(paths).map { |path| normalize(path) }
        raise "checkpoint includes an unsafe path" if selected.any?(&:nil?)
        selected = selected.uniq
        raise "checkpoint includes a path outside the transaction" unless (selected - @paths).empty?

        selected.each do |path|
          @snapshots[path] = snapshot(path)
          @seen[path] = [fingerprint(absolute(path))]
        end
        @state = "open"
        @delivery_head_before = nil
        @delivery_head_after = nil
        persist!
        emit("fix:transaction_checkpoint", id: @id, paths: selected)
        Result.ok(selected)
      rescue StandardError => e
        emit("fix:transaction_checkpoint_failed", id: @id, error: e.message)
        Result.err("transaction checkpoint: #{e.message}", category: :infrastructure)
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

      # Stops tracking paths that changed under the pass without its write: they are neither
      # delivered nor rolled back, so another writer's work stays as that writer left it.
      def release!(paths)
        released = Array(paths).filter_map { |path| normalize(path) } & @paths
        @paths -= released

        released.each { |path| @snapshots.delete(path) && @seen.delete(path) }
        persist!
        emit("fix:transaction_release", id: @id, paths: released) unless released.empty?
        released
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
        # Recovery is a writer too: serialize it against a live /fix transaction.
        # Nonblocking acquisition avoids hanging an operator while another run
        # owns the root-wide lock; preserve the manifest and report the blocker.
        unless acquire_lock(nonblock: true)
          return Result.err(
            "transaction recovery refused: an active transaction holds the root lock",
            category: :infrastructure,
          )
        end

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

      def acquire_lock(nonblock: false)
        verify_root_storage_tree!
        path = File.join(@root, LOCK)
        raise "transaction lock path is a symlink" if File.symlink?(path)
        @lock = File.open(path, File::RDWR | File::CREAT, 0o600)
        flags = File::LOCK_EX
        flags |= File::LOCK_NB if nonblock
        locked = @lock.flock(flags)
        return true if locked

        release_lock
        false
      rescue StandardError
        release_lock
        raise
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
        return unless inside?(full, File.expand_path(@root)) || inside?(full, outer_root)

        Pathname.new(full).relative_path_from(File.expand_path(@root)).to_s
      end

      # A /fix run rooted in MASTER may repair a RAILS or OPENBSD file beside it: the transaction
      # snapshots and restores any file in the repository MASTER sits in, named relative to MASTER.
      def outer_root
        return File.expand_path(@root) unless defined?(Master::REPO_ROOT)

        repo = File.expand_path(Master::REPO_ROOT)
        inside?(File.expand_path(@root), repo) ? repo : File.expand_path(@root)
      end

      def inside?(path, dir) = path == dir || path.start_with?(dir + File::SEPARATOR)

      # Resolve the parent directory before every snapshot/restore. Lexical
      # containment alone permits a path below a symlinked directory to escape
      # the checkout and make rollback write outside the repository.
      def absolute(path)
        candidate = File.expand_path(path, @root)
        return File.realpath(@root) if candidate == File.expand_path(@root)

        parent = File.realpath(File.dirname(candidate))
        allowed_roots = [@root, outer_root].map { |root| File.realpath(root) }.uniq
        unless allowed_roots.any? { |root| inside?(parent, root) }
          raise "transaction path escapes through a symlinked parent: #{path}"
        end

        File.join(parent, File.basename(candidate))
      rescue Errno::ENOENT => e
        raise "transaction parent is unavailable for #{path}: #{e.message}"
      end

      def snapshot(path, versioned: false)
        abs = absolute(path)
        return Snapshot.new(path, false, :missing, nil, nil, nil) unless File.exist?(abs) || File.symlink?(abs)

        stat = File.lstat(abs)
        if stat.symlink?
          Snapshot.new(path, true, :symlink, stat.mode & 0o7777, File.readlink(abs), nil)
        elsif stat.file?
          name = encoded(path)
          name = "#{name}.#{SecureRandom.hex(8)}" if versioned
          store = File.join(@dir, "files", name)
          snapshot_file(abs, store)
          Snapshot.new(path, true, :file, stat.mode & 0o7777, nil, store)
        else
          Snapshot.new(path, true, :other, stat.mode & 0o7777, nil, nil)
        end
      end

      def snapshot_file(source, destination)
        verify_storage_tree!(create_files: true)
        expected_dir = File.expand_path(File.join(@dir, "files"))
        raise "snapshot store path escapes the transaction directory" unless File.dirname(File.expand_path(destination)) == expected_dir
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
        verify_storage_tree!
        manifest_path = File.join(@dir, MANIFEST)
        raise "transaction manifest is a symlink" if File.symlink?(manifest_path)
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
        write_atomic(manifest_path, JSON.pretty_generate(manifest) + "\n", mode: 0o600)
      end

      def load_manifest!
        verify_storage_tree!
        path = File.join(@dir, MANIFEST)
        raise "transaction manifest is a symlink" if File.symlink?(path)
        raise "transaction manifest not found: #{@id}" unless File.file?(path)

        data = JSON.parse(File.read(path, encoding: "UTF-8"))
        validate_manifest!(data)

        @state = data.fetch("state")
        @delivery_head_before = data["delivery_head_before"]
        @delivery_head_after = data["delivery_head_after"]
        @paths = data.fetch("paths")
        @seen = Hash.new { |hash, key| hash[key] = [] }
        data.fetch("seen").each { |key, values| @seen[key] = values }
        @snapshots = data.fetch("snapshots").to_h.transform_values do |raw|
          Snapshot.new(raw["path"], raw["exists"], raw["kind"].to_sym, raw["mode"], raw["link"], raw["store"])
        end
        cleanup_orphan_snapshots!
        true
      rescue JSON::ParserError => e
        raise "transaction manifest is corrupt: #{e.message}"
      end

      # A recovery manifest is persisted local state, not authority to write
      # arbitrary paths or to restore bytes from arbitrary files.
      def validate_manifest!(data)
        raise "transaction manifest malformed" unless data.is_a?(Hash) && data["version"].to_i == 1
        raise "transaction manifest identity mismatch" unless data["id"] == @id
        raise "transaction manifest state unsupported" unless VALID_STATES.include?(data["state"])

        raw_paths = data["paths"]
        raise "transaction manifest paths malformed" unless raw_paths.is_a?(Array) && raw_paths.all? { |item| item.is_a?(String) }
        paths = raw_paths.map do |item|
          normalized = normalize(item)
          raise "transaction manifest contains unsafe or non-canonical path: #{item}" unless normalized == item && item != "."

          normalized
        end
        raise "transaction manifest contains duplicate paths" unless paths.uniq == paths

        raw_snapshots = data["snapshots"]
        raise "transaction manifest snapshots malformed" unless raw_snapshots.is_a?(Hash)
        raise "transaction manifest snapshot set mismatch" unless raw_snapshots.keys.sort == paths.sort

        raw_snapshots.each do |path, snapshot|
          validate_snapshot_record!(path, snapshot, require_store: data["state"] == "open")
        end
        raw_seen = data["seen"]
        raise "transaction manifest fingerprints malformed" unless raw_seen.is_a?(Hash)
        raw_seen.each do |path, fingerprints|
          raise "transaction manifest fingerprint path is unsafe: #{path}" unless paths.include?(path)
          raise "transaction manifest fingerprints malformed for #{path}" unless fingerprints.is_a?(Array) && fingerprints.all? { |item| item.is_a?(String) }
        end
        raise "transaction manifest is missing path fingerprints" unless (paths - raw_seen.keys).empty?

        true
      end

      def validate_snapshot_record!(path, snapshot, require_store:)
        raise "transaction manifest snapshot malformed: #{path}" unless snapshot.is_a?(Hash) && snapshot["path"] == path
        kind = snapshot["kind"]
        exists = snapshot["exists"]
        mode = snapshot["mode"]
        link = snapshot["link"]
        store = snapshot["store"]
        valid_mode = mode.is_a?(Integer) && mode.between?(0, 0o7777)

        case kind
        when "missing"
          valid = exists == false && mode.nil? && link.nil? && store.nil?
        when "file"
          files_dir = File.expand_path(File.join(@dir, "files"))
          store_path = store.is_a?(String) ? File.expand_path(store) : nil
          store_name = store_path && File.basename(store_path)
          store_name_pattern = /\A#{Regexp.escape(encoded(path))}(?:\.[0-9a-f]{16})?\z/
          stored_path_valid = store_path && File.dirname(store_path) == files_dir &&
                              store_name.match?(store_name_pattern)
          stored_bytes_valid = !require_store || (
            File.directory?(files_dir) && !File.symlink?(files_dir) &&
            File.file?(store_path) && !File.symlink?(store_path)
          )
          valid = exists == true && valid_mode && link.nil? && stored_path_valid && stored_bytes_valid
        when "symlink"
          valid = exists == true && valid_mode && link.is_a?(String) && store.nil?
        when "other"
          valid = !require_store && exists == true && valid_mode && link.nil? && store.nil?
        else
          valid = false
        end
        raise "transaction manifest snapshot invalid: #{path}" unless valid
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
        verify_root_storage_tree!
        raise "transaction directory changed type" if File.symlink?(@dir)
        return nil unless Dir.exist?(@dir)

        expected_parent = File.realpath(File.join(@root, ROOT_DIR))
        raise "transaction directory parent changed" unless File.realpath(File.dirname(@dir)) == expected_parent
        FileUtils.rm_rf(@dir)
        parent = File.dirname(@dir)
        FileUtils.rmdir(parent) if Dir.exist?(parent) && Dir.empty?(parent)
      rescue SystemCallError, RuntimeError
        nil
      end

      def verify_root_storage_tree!
        master_dir = File.join(@root, ".master")
        transaction_root = File.join(@root, ROOT_DIR)
        raise "MASTER state directory is a symlink" if File.symlink?(master_dir)
        FileUtils.mkdir_p(master_dir)
        raise "MASTER state path is not a real directory" unless File.directory?(master_dir) && !File.symlink?(master_dir)
        raise "transaction root is a symlink" if File.symlink?(transaction_root)
        FileUtils.mkdir_p(transaction_root)
        raise "transaction root is not a real directory" unless File.directory?(transaction_root) && !File.symlink?(transaction_root)
      end

      def verify_storage_tree!(create_files: false)
        verify_root_storage_tree!
        raise "transaction directory is a symlink" if File.symlink?(@dir)
        raise "transaction directory is unavailable" unless File.directory?(@dir)

        files_dir = File.join(@dir, "files")
        raise "transaction snapshot directory is a symlink" if File.symlink?(files_dir)
        FileUtils.mkdir_p(files_dir) if create_files
        return true unless File.exist?(files_dir)

        raise "transaction snapshot path is not a real directory" unless File.directory?(files_dir) && !File.symlink?(files_dir)
        true
      end

      def duplicate_seen
        copy = Hash.new { |hash, path| hash[path] = [] }
        @seen.each { |path, values| copy[path] = values.dup }
        copy
      end

      def snapshot_matches_fingerprint?(path, snapshot, current)
        case snapshot.kind
        when :missing
          current == "missing"
        when :file
          current == "file:#{Digest::SHA256.file(snapshot.store)}"
        when :symlink
          absolute_path = absolute(path)
          stat = File.lstat(absolute_path)
          stat.symlink? && (stat.mode & 0o7777) == snapshot.mode && File.readlink(absolute_path) == snapshot.link
        else
          false
        end
      rescue StandardError
        false
      end

      def persisted_state_matches?(state:, paths:, snapshots:)
        manifest_path = File.join(@dir, MANIFEST)
        return false if File.symlink?(manifest_path) || !File.file?(manifest_path)

        data = JSON.parse(File.read(manifest_path, encoding: "UTF-8"))
        return false unless data["state"] == state && data["paths"] == paths

        snapshots.all? do |path, item|
          record = data.fetch("snapshots", {})[path]
          record.is_a?(Hash) && record["store"] == item.store && record["kind"] == item.kind.to_s
        end
      rescue StandardError
        false
      end

      def discard_snapshots!(snapshots)
        root = File.expand_path(File.join(@dir, "files"))
        referenced = @snapshots.values.filter_map(&:store).map { |path| File.expand_path(path) }.to_set
        Array(snapshots).each do |item|
          next unless item&.kind == :file && item.store

          path = File.expand_path(item.store)
          next unless File.dirname(path) == root
          next if referenced.include?(path)

          File.delete(path) if File.file?(path) || File.symlink?(path)
        rescue SystemCallError
          nil
        end
      end

      def cleanup_orphan_snapshots!
        files_dir = File.join(@dir, "files")
        return unless Dir.exist?(files_dir) && !File.symlink?(files_dir)

        referenced = @snapshots.values.filter_map(&:store).map { |path| File.expand_path(path) }.to_set
        Dir.children(files_dir).each do |name|
          path = File.join(files_dir, name)
          next if referenced.include?(File.expand_path(path))
          next unless File.file?(path) || File.symlink?(path)

          File.delete(path)
        rescue SystemCallError
          nil
        end
      end

      def encoded(path) = Digest::SHA256.hexdigest(path)[0, 24]
    end
  end
end
