# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "pathname"
require "securerandom"
require_relative "../io/atomic_write"
require_relative "../core/world"
require_relative "../trace/mutation_observer"
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

      def self.normalize_id(id)
        value = id.to_s
        raise ArgumentError, "transaction id is unsafe" unless value.match?(%r{\A[a-zA-Z0-9_-]+\z})

        value
      end
      private_class_method :normalize_id

      def initialize(root:, paths:, id: SecureRandom.hex(10), bus: nil)
        @root = File.expand_path(root)
        @paths = Array(paths).map { |path| normalize(path) }
        raise "transaction contains an unsafe path" if @paths.any?(&:nil?)
        @paths.uniq!
        @id = self.class.send(:normalize_id, id)
        @bus = bus
        @lifecycle_observer = Master::Trace::MutationObserver.new(
          root: @root, namespace: "fix:transaction_lifecycle",
          subject_type: "transaction", subject_id: @id, bus: @bus
        )
        @pending_marker_owned = false
        @seen = Hash.new { |hash, path| hash[path] = [] }
        @snapshots = {}
        @dir = File.join(@root, ROOT_DIR, @id)
        @lock = nil
        @active = false
        @state = "new"
      end

      def begin!
        raise "transaction already active" if @active
        created_dir = false
        acquire_lock
        raise "transaction id already exists: #{@id}" if File.exist?(@dir) || File.symlink?(@dir)

        lifecycle_mutation(:begin, item_count: @paths.size) do
          Dir.mkdir(@dir, 0o700)
          created_dir = true
          @paths.each do |path|
            @snapshots[path] = snapshot(path)
            raise "transaction cannot safely track unsupported filesystem object" if @snapshots[path].kind == :other
          end
          @state = "open"
          @active = true
          observe!(verify_snapshot: true)
          emit("fix:transaction_snapshot_summary", id: @id, tracked_paths: @paths.size)
          emit("fix:transaction_start", id: @id, paths: @paths)
          self
        end
      rescue StandardError
        @active = false
        if pending_marker? || persisted? || !created_dir
          release_lock
        else
          cleanup!
          release_lock
        end
        raise
      end

      def observe!(verify_snapshot: false)
        @paths.each do |path|
          current = fingerprint(absolute(path))
          if verify_snapshot && !snapshot_matches_fingerprint?(@snapshots.fetch(path), current)
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
        staged = added.to_h { |path| [path, snapshot(path)] }
        return Result.err("transaction source changed during enlistment", category: :policy) unless
          added.all? { |path| snapshot_matches_fingerprint?(staged.fetch(path), fingerprint(absolute(path))) }

        old = [@paths, @snapshots]
        @snapshots = @snapshots.merge(staged)
        @paths = (@paths + added).uniq
        observed = observe_paths!(added) unless added.empty?
        if observed&.err?
          @paths, @snapshots = old unless persisted_state_matches?
          return observed
        end

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

        old_seen = @seen
        @seen = @seen.to_h.transform_values(&:dup).tap { |seen| seen.default_proc = ->(hash, path) { hash[path] = [] } }
        selected.each do |path|
          @seen[path] << fingerprint(absolute(path))
          @seen[path] = @seen[path].uniq.last(8)
        end
        persist!
        emit("fix:transaction_paths_observed", id: @id, paths: selected)
        Result.ok(selected)
      rescue StandardError => e
        @seen = old_seen if defined?(old_seen) && !persisted_state_matches?
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

        lifecycle_mutation(:checkpoint, item_count: selected.size) do
          staged = selected.to_h { |path| [path, snapshot(path, versioned: true)] }
          if staged.values.any? { |item| item.kind == :other }
            Result.err("checkpoint cannot safely capture a directory", category: :policy)
          elsif !selected.all? { |path| snapshot_matches_fingerprint?(staged.fetch(path), fingerprint(absolute(path))) }
            Result.err("transaction source changed while checkpointing", category: :policy)
          else
            old = [@snapshots, @seen, @state, @delivery_head_before, @delivery_head_after]
            old_stores = selected.filter_map { |path| @snapshots[path]&.store }
            @snapshots = @snapshots.merge(staged)
            @seen = @seen.to_h.transform_values(&:dup)
            @seen.default_proc = ->(hash, path) { hash[path] = [] }
            selected.each { |path| @seen[path] = [fingerprint(absolute(path))] }
            @state = "open"
            @delivery_head_before = @delivery_head_after = nil
            persist!
            old_stores.each { |store| File.delete(store) if store && !@snapshots.values.any? { |item| item.store == store } }
            emit("fix:transaction_checkpoint", id: @id, paths: selected)
            Result.ok(selected)
          end
        end
      rescue StandardError => e
        raise if @lifecycle_observer.failed?

        @snapshots, @seen, @state, @delivery_head_before, @delivery_head_after = old if defined?(old) && !persisted_state_matches?
        emit("fix:transaction_checkpoint_failed", id: @id, error: e.message)
        Result.err("transaction checkpoint: #{e.class}", category: :infrastructure)
      end

      def finalize!
        raise "transaction not active" unless @active

        lifecycle_mutation(:finalize, item_count: @paths.size) do
          @state = "committed"
          @active = false
          persist!
          Result.ok(@paths)
        end
        cleanup!
        release_lock
        emit("fix:transaction_commit", id: @id, paths: @paths)
        Result.ok(@paths)
      rescue StandardError => e
        emit("fix:transaction_commit_failed", id: @id, error: e.message)
        @active = false
        release_lock
        Result.err("transaction finalize: #{e.class}", category: :infrastructure)
      end

      def rollback!
        # A committed pass is delivered work; undoing it is a new change, never a rollback.
        if %w[committed rolled_back].include?(@state)
          return Result.err("rollback refused: transaction already #{@state.tr("_", " ")}", category: :policy)
        end
        raise "transaction not active" unless @active || persisted?
        return delivery.preserve! if @state == "delivering" && delivery.pending?

        result = lifecycle_mutation(:rollback, item_count: @paths.size) do
          @state = "open" if @state == "delivering"
          @delivery_head_before = nil if @state == "open"
          current_conflicts = conflicts()
          current_conflicts.empty? ? restore_snapshots_and_roll_back : reject_rollback_conflict(current_conflicts)
        end

        if @state == "rolled_back"
          cleanup!
          @active = false
          release_lock
          emit("fix:transaction_rollback", id: @id, paths: @paths)
        elsif @state == "conflict"
          @active = false
          release_lock
          emit("fix:transaction_conflict", id: @id, paths: @paths)
        end
        result
      rescue StandardError => e
        emit("fix:transaction_rollback_failed", id: @id, error: e.message)
        @active = false
        release_lock
        Result.err("transaction rollback: #{e.class}", category: :infrastructure)
      end

      # Stops tracking paths that changed under the pass without its write: they are neither
      # delivered nor rolled back, so another writer's work stays as that writer left it.
      def release!(paths)
        released = Array(paths).filter_map { |path| normalize(path) } & @paths
        return [] if released.empty?

        lifecycle_mutation(:release, item_count: released.size) do
          @paths -= released
          released.each { |path| @snapshots.delete(path) && @seen.delete(path) }
          persist!
          emit("fix:transaction_release", id: @id, paths: released)
          released
        end
      end

      def conflicts
        @paths.reject { |path| @seen[path].include?(fingerprint(absolute(path))) }
      end

      # Before a rollback of an open pass: another writer's edits leave the transaction, so the
      # rollback restores the pass's own writes and leaves theirs. Answers the paths released.
      def release_conflicts!
        return [] unless @active && @state == "open"

        release!(conflicts)
      end

      # The paths among these that this transaction tracks, in its own spelling.
      def tracked(paths) = Array(paths).filter_map { |path| normalize(path) } & @paths

      def id = @id
      def state = @state
      def active? = @active

      private

      def reject_rollback_conflict(conflicts)
        @state = "conflict"
        persist!
        Result.err("rollback refused: concurrent changes in #{conflicts.size} path(s)", category: :policy)
      end

      def restore_snapshots_and_roll_back
        @snapshots.each { |path, snap| restore(path, snap) }
        @state = "rolled_back"
        persist!
        Result.ok(@paths)
      end

      # Reached only via Recovery.recover! (load_persisted(...).send(:recover!))
      # -- nothing else calls an instance's own recover! directly, confirmed
      # by grepping every lib/ and test/ caller before making this private.
      def recover!(release_conflicts: false)
        return Result.err("transaction recovery refused: an active transaction holds the root lock", category: :infrastructure) unless acquire_lock(nonblock: true)
        refusal = resolve_pending_marker!
        return refusal if refusal

        load_manifest!
        recover_for_state(release_conflicts:)
      rescue StandardError => e
        emit("fix:transaction_recovery_failed", id: @id, error: e.message)
        Result.err("transaction recovery: #{e.message}", category: :infrastructure)
      ensure
        release_lock
      end

      def recover_for_state(release_conflicts: false)
        case @state
        when "open" then recover_open_state(release_conflicts:)
        when "delivering" then delivery.send(:recover!)
        when "committed", "rolled_back" then recover_terminal_state
        when "conflict" then recover_error_state("transaction recovery found a concurrent edit", :policy)
        when "trace_failed" then recover_error_state("transaction lifecycle audit failed; manual review required", :infrastructure)
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

      def recover_error_state(message, category) = Result.err(message, category:)

      def recover_open_state(release_conflicts: false)
        @active = true
        name_released(release_conflicts!) if release_conflicts

        result = rollback!
        emit("fix:transaction_recovered", id: @id, result: result.to_s)
        result
      end

      def name_released(paths)
        return if paths.empty?

        Master::Trace::Dmesg.status(
          "fix0", "stranded transaction #{@id}: kept #{paths.size} file(s) another writer changed since: " \
                  "#{paths.first(5).join(", ")}"
        )
      end

      # Transaction events are diagnostic telemetry, not the durable manifest.
      # Never persist raw workspace paths or free-form errors/results here: paths
      # live in the protected transaction manifest, and actionable errors remain
      # in the local Result/exception for the operator.
      def emit(event, **payload)
        safe = payload.dup
        if safe.key?(:paths)
          paths = Array(safe.delete(:paths)).map(&:to_s).sort
          safe[:paths_count] = paths.size
          safe[:paths_digest] = Digest::SHA256.hexdigest(paths.join("\0"))
        end

        %i[error result message detail output].each do |key|
          value = safe.delete(key)
          next unless value.is_a?(String)

          safe["#{key}_digest".to_sym] = Digest::SHA256.hexdigest(value)
          safe["#{key}_bytes".to_sym] = value.bytesize
        end
        safe[:schema_version] = 1 unless safe.key?(:schema_version)
        @bus&.publish(event, **safe)
      rescue StandardError => e
        warn("trace0: #{e.class}: event publication failed") if ENV["MASTER_TRACE_STRICT"] == "1"
        nil
      end

      def lifecycle_mutation(operation, item_count: nil)
        @lifecycle_observer.mutate(operation:, item_count:) do
          create_pending_marker!(operation)
          yield
        end.tap do
          remove_pending_marker! if @pending_marker_owned
        end
      rescue StandardError
        if @lifecycle_observer.failed?
          @state = "trace_failed"
          begin
            persist! if persisted?
          rescue StandardError
            nil
          end
        elsif @pending_marker_owned
          begin
            remove_pending_marker!
          rescue StandardError
            nil
          end
        end
        raise
      end

      def pending_marker_path = File.join(@root, ROOT_DIR, ".pending-#{@id}")

      def pending_marker?
        File.exist?(pending_marker_path) || File.symlink?(pending_marker_path)
      rescue SystemCallError
        true
      end

      MARKER_REFUSED = "transaction recovery refused: a lifecycle audit is incomplete; manual review required"

      # Runs under the root lock, so no live transaction is mid-mutation. A marker
      # whose writer is gone is resolved once the manifest loads and validates;
      # one a live process holds, a symlink, or a manifest that does not load
      # stays refused. Answers the refusal, or nil to proceed.
      def resolve_pending_marker!
        label = File.join(ROOT_DIR, File.basename(pending_marker_path))

        refusal = Master::Trace::MutationObserver::PendingMarker.resolve(pending_marker_path, label:) do
          load_manifest!
          "transaction #{@id} manifest loads, state=#{@state}"
        end

        Result.err("#{MARKER_REFUSED}: #{refusal}", category: :infrastructure) if refusal
      end

      def create_pending_marker!(operation)
        path = pending_marker_path
        raise "transaction lifecycle marker is a symlink" if File.symlink?(path)
        Master::Trace::MutationObserver::PendingMarker.write!(path, operation:, subject: @id)
        @pending_marker_owned = true
      end

      def remove_pending_marker!
        path = pending_marker_path
        File.delete(path) if File.exist?(path)
        @pending_marker_owned = false
        true
      end

      SAFE_EVENT_KEYS = %w[
        id state category result commit head_before head_after operation result_state
        tracked_paths path_count finding_count argument_count item_count elapsed_ms
        turn attempt tries resume_count remaining_seconds
      ].freeze

      def safe_event_payload(payload)
        safe = {}
        payload.each do |key, value|
          name = key.to_s
          case name
          when "paths"
            safe[:path_count] = Array(value).size
          when "path", "target"
            safe["#{name}_present".to_sym] = !value.to_s.empty?
          when "error"
            safe[:error_present] = !value.to_s.empty?
          when "message", "reason"
            safe["#{name}_present".to_sym] = !value.to_s.empty?
          when "findings"
            safe[:finding_count] = Array(value).size
          else
            next unless SAFE_EVENT_KEYS.include?(name)
            if value.is_a?(Numeric) || value == true || value == false
              safe[name.to_sym] = value
            elsif value.is_a?(String) || value.is_a?(Symbol)
              text = value.to_s
              safe[name.to_sym] = text if text.match?(/\A[a-zA-Z0-9_.:-]{1,128}\z/)
            end
          end
        end
        safe
      end

      def persisted? = File.file?(File.join(@dir, MANIFEST))

      def acquire_lock(nonblock: false)
        master_dir = File.join(@root, ".master")
        tx_root = File.join(@root, ROOT_DIR)
        raise "MASTER state directory is a symlink" if File.symlink?(master_dir)
        raise "transaction root is a symlink" if File.symlink?(tx_root)
        FileUtils.mkdir_p(tx_root)
        path = File.join(@root, LOCK)
        raise "transaction lock path is a symlink" if File.symlink?(path)
        @lock = File.open(path, File::RDWR | File::CREAT, 0o600)
        locked = @lock.flock(File::LOCK_EX | (nonblock ? File::LOCK_NB : 0))
        release_lock unless locked
        !!locked
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

      def absolute(path) = path_guard.send(:within, File.join(@root, path))
      def path_guard = (@path_guard ||= Master::Core::World.allocate.tap { |world| world.instance_variable_set(:@root, outer_root) })

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
        raise "transaction snapshot storage is a symlink" if [File.join(@root, ".master"), File.join(@root, ROOT_DIR), @dir, File.join(@dir, "files")].any? { |path| File.symlink?(path) }
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
        raise "transaction storage path is a symlink" if [File.join(@root, ".master"), File.join(@root, ROOT_DIR), @dir, File.join(@dir, "files"), File.join(@dir, MANIFEST)].any? { |path| File.symlink?(path) }
        manifest = {
          "version" => 1,
          "id" => @id,
          "state" => @state,
          "delivery_head_before" => @delivery_head_before,
          "delivery_head_after" => @delivery_head_after,
          "delivery_marked" => @delivery_marked == true,
          "paths" => @paths,
          "seen" => @seen,
          "snapshots" => @snapshots.transform_values(&:to_h),
        }
        write_atomic(File.join(@dir, MANIFEST), JSON.pretty_generate(manifest) + "\n", mode: 0o600)
      end

      def load_manifest!
        raise "transaction recovery storage is a symlink" if [File.join(@root, ".master"), File.join(@root, ROOT_DIR), @dir, File.join(@dir, "files")].any? { |item| File.symlink?(item) }
        path = File.join(@dir, MANIFEST)
        raise "transaction manifest is a symlink" if File.symlink?(path)
        raise "transaction manifest not found: #{@id}" unless File.file?(path)

        data = JSON.parse(File.read(path, encoding: "UTF-8"))
        validate_manifest!(data)
        @state = data.fetch("state")
        @delivery_head_before = data["delivery_head_before"]
        @delivery_head_after = data["delivery_head_after"]
        @delivery_marked = data["delivery_marked"] == true
        @paths = data.fetch("paths")
        @seen = Hash.new { |hash, key| hash[key] = [] }
        data.fetch("seen").each { |key, values| @seen[key] = values }
        @snapshots = data["snapshots"].to_h.transform_values do |raw|
          Snapshot.new(raw["path"], raw["exists"], raw["kind"].to_sym, raw["mode"], raw["link"], raw["store"])
        end
        true
      rescue JSON::ParserError => e
        raise "transaction manifest is corrupt: #{e.message}"
      end

      def validate_manifest!(data)
        raise "transaction manifest malformed" unless data.is_a?(Hash) && data["version"].to_i == 1 && data["id"] == @id
        state, paths, snapshots, seen = data.values_at("state", "paths", "snapshots", "seen")
        raise "transaction manifest state unsupported" unless %w[open delivering committed rolled_back conflict trace_failed].include?(state)
        raise "transaction manifest delivery mark malformed" unless [nil, true, false].include?(data["delivery_marked"])
        raise "transaction manifest delivery heads malformed" unless data.values_at("delivery_head_before", "delivery_head_after").all? { |head| head.nil? || head.is_a?(String) }
        raise "transaction manifest paths malformed: unsafe or non-canonical path" unless paths.is_a?(Array) && paths.all? { |p| p.is_a?(String) && p != "." && normalize(p) == p }
        raise "transaction manifest snapshot set mismatch" unless snapshots.is_a?(Hash) && snapshots.keys.sort == paths.sort

        paths.each do |path|
          item = snapshots[path]
          valid = item.is_a?(Hash) && item["path"] == path && %w[missing file symlink].include?(item["kind"]) &&
                  (item["kind"] == "missing" ? item["exists"] == false && item["mode"].nil? :
                    item["exists"] == true && item["mode"].is_a?(Integer) && item["mode"].between?(0, 0o7777))
          raise "transaction manifest snapshot invalid: #{path}" unless valid
          if item["kind"] == "symlink"
            link = item["link"]
            target = link.is_a?(String) ? File.expand_path(link, File.dirname(File.join(@root, path))) : ""
            raise "transaction manifest snapshot invalid: #{path}" unless link.is_a?(String) && item["store"].nil? && path_guard.send(:within, target) == target
          elsif item["kind"] == "file"
            store = item["store"].to_s
            dir = File.expand_path(File.join(@dir, "files"))
            valid = item["link"].nil? && File.dirname(File.expand_path(store)) == dir &&
                    File.basename(store).match?(/\A#{Regexp.escape(encoded(path))}(?:\.[0-9a-f]{16})?\z/) &&
                    !File.symlink?(store) && !File.directory?(store) && (!%w[open delivering].include?(state) || File.file?(store))
            raise "transaction manifest snapshot invalid: #{path}" unless valid
          else
            raise "transaction manifest snapshot invalid: #{path}" if item["link"] || item["store"]
          end
        end
        raise "transaction manifest fingerprints malformed" unless seen.is_a?(Hash) && seen.keys.sort == paths.sort && paths.all? { |p| seen[p].is_a?(Array) && seen[p].all? { |v| v.is_a?(String) } }
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
        return if [File.join(@root, ".master"), File.join(@root, ROOT_DIR), @dir].any? { |path| File.symlink?(path) }
        FileUtils.rm_rf(@dir)
        parent = File.dirname(@dir)
        FileUtils.rmdir(parent) if Dir.exist?(parent) && Dir.empty?(parent)
      rescue SystemCallError
        nil
      end

      def snapshot_matches_fingerprint?(snapshot, current)
        return current == "missing" if snapshot.kind == :missing
        return current == fingerprint(snapshot.store) if snapshot.kind == :file

        snapshot.kind == :symlink && current.start_with?("symlink:") && current.split(":", 3).last == snapshot.link
      rescue StandardError
        false
      end

      def persisted_state_matches?
        return false if [File.join(@root, ".master"), File.join(@root, ROOT_DIR), @dir, File.join(@dir, MANIFEST)].any? { |path| File.symlink?(path) }
        data = JSON.parse(File.read(File.join(@dir, MANIFEST), encoding: "UTF-8"))
        data["state"] == @state && data["paths"] == @paths && data["seen"] == @seen &&
          data["snapshots"] == JSON.parse(JSON.generate(@snapshots.transform_values(&:to_h)))
      rescue StandardError
        false
      end

      def encoded(path) = Digest::SHA256.hexdigest(path)[0, 24]
    end
  end
end
