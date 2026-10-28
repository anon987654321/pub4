# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require_relative "../io/exec"
require "securerandom"
require "tempfile"
require "time"
require "yaml"
require_relative "run_journal"

module Master
  module Fix
    # The small, auditable repair core. Existing /fix stages remain its
    # compatibility adapter until their laws have migrated with proof.
    class Kernel
      GENESIS = "0" * 64
      MANIFEST = ".pub4"
      LOG_RELATIVE_PATH = ".master/log.jsonl"
      MAX_TEXT_BYTES = 2 * 1024 * 1024
      IGNORED_DIRECTORIES = %w[.git .master node_modules vendor tmp coverage .bundle].freeze
      ACCESS = %w[none read write read_write].freeze

      FileState = Data.define(:path, :content, :hash, :bytes, :kind, :mode)
      Observation = Data.define(
        :command, :output, :hash, :files, :deleted_paths, :modified_paths,
        :tree, :scope, :manifest_root, :sacred_paths, :seq
      ) do
        def file(path)
          files[path.to_s.sub(%r{\A\./}, "")]
        end

        def deleted = deleted_paths
        def modified = modified_paths

        def sacred_path?(path)
          return true if sacred_paths.include?("*")

          candidate = path.to_s.tr("\\", "/").sub(%r{\A\./}, "")
          sacred_paths.any? do |prefix|
            value = prefix.to_s.tr("\\", "/").sub(%r{\A\./}, "")
            candidate == value.delete_suffix("/") ||
              (value.end_with?("/") && candidate.start_with?(value)) ||
              candidate.start_with?("#{value.delete_suffix("/")}/")
          end
        end
      end

      Law = Data.define(:name, :sacred, :automatic, :check, :repair)
      Change = Data.define(:path, :before_hash, :after_hash, :before_content, :after_content, :diff, :mode)
      Repair = Data.define(:law, :target, :tree, :observation_hash, :before_hash, :after_hash, :diff, :changes, :run_id)
      Outcome = Data.define(:state, :run_id, :iterations, :reason, :observation, :repair)

      class BoundaryViolation < StandardError
        attr_reader :tree, :actor, :required, :granted

        def initialize(tree:, actor:, required:, granted:)
          @tree, @actor, @required, @granted = tree, actor, required, granted
          super("tree #{tree} grants #{granted} to #{actor}; #{required} access is required")
        end
      end

      class LedgerCorruption < StandardError; end

      def initialize(root:, actor: "master", laws: nil, log_path: nil, bus: nil, lifecycle_journal: nil)
        @root = File.expand_path(root)
        @workspace_root = locate_workspace(@root)
        @actor = actor.to_s
        @laws = laws
        @bus = bus
        @log_path = File.expand_path(log_path || File.join(@workspace_root, LOG_RELATIVE_PATH))
        @log_head = nil
        @lifecycle_journal = lifecycle_journal
        @lifecycle_mutex = Mutex.new
        @execution_mutex = Mutex.new
      end

      attr_reader :root, :workspace_root, :actor, :log_path

      # The Kernel owns /fix lifecycle coordination. RunJournal is currently its
      # durable metadata adapter; no caller should construct a second journal for
      # the same coordinator. Keeping it behind this accessor makes the migration
      # incremental without changing the persisted format or recovery contract.
      def lifecycle_journal
        @lifecycle_mutex.synchronize do
          @lifecycle_journal ||= RunJournal.new(root: @root, bus: @bus)
        end
      end

      alias run_journal lifecycle_journal

      # Production factories make Kernel the shared owner while the old loop
      # classes remain behavior-preserving adapters until their parity gates pass.
      def build_fix_loop(**options)
        require_relative "fix_loop" unless defined?(FixLoop)
        FixLoop.new(**options, kernel: self)
      end

      def build_repair_loop(**options)
        require_relative "repair_loop" unless defined?(RepairLoop)
        RepairLoop.new(**options, kernel: self)
      end

      # Execute the convergence adapter under the single Kernel-owned lock and
      # lifecycle boundary. The adapter still owns the per-pass implementation,
      # but only Kernel starts, terminalizes, and correlates the overall run.
      def run_fix_loop(adapter, target:, max_passes:, budget_seconds:, incremental:, requested:, cancellation: nil)
        @execution_mutex.synchronize do
          coordinator_run_id = nil
          previous_cancellation = adapter.instance_variable_get(:@cancellation)
          previous_run_id = Fiber[:master_fix_kernel_run_id]
          begin
            adapter.instance_variable_set(:@cancellation, cancellation)
            cancellation.activate! if cancellation&.respond_to?(:activate!)
            coordinator_run_id = begin_coordinated_run(target:, max_passes:, budget_seconds:, requested:)
            Fiber[:master_fix_kernel_run_id] = coordinator_run_id
            result = adapter.run_unlocked(
              target, max_passes:, budget_seconds:, incremental:, requested:
            )
            state = adapter.last_terminal_state || OutcomePolicy.terminal_state(result) || :unknown_outcome
            finish_coordinated_run(run_id: coordinator_run_id, state:, outcome: result)
            result
          rescue StandardError => error
            if coordinator_run_id
              begin
                finish_coordinated_run(run_id: coordinator_run_id, state: :unknown_outcome, error:)
              rescue StandardError => journal_error
                Master::Ground::Swallow.log(
                  journal_error, context: "fix_kernel.coordinator_terminal", event_bus: @bus
                )
              end
            end
            raise
          ensure
            Fiber[:master_fix_kernel_run_id] = previous_run_id
            adapter.instance_variable_set(:@cancellation, previous_cancellation)
          end
        end
      end

      # Hash-chained operational evidence around the legacy convergence adapter.
      # Detailed pass and recovery state still lives in lifecycle_journal.
      def begin_coordinated_run(target:, max_passes:, budget_seconds:, requested:)
        run_id = SecureRandom.hex(12)
        expanded = File.expand_path(target.to_s, @root)
        target_label = if expanded == @workspace_root
                         "."
                       elsif expanded.start_with?(@workspace_root + File::SEPARATOR)
                         expanded.delete_prefix(@workspace_root + File::SEPARATOR)
                       else
                         "(external target)"
                       end
        append_event("coordinator_started", {
          actor: @actor, target: target_label, max_passes: Integer(max_passes),
          budget_seconds: Integer(budget_seconds), requested: requested == true
        }, run_id:)
        run_id
      end

      def finish_coordinated_run(run_id:, state:, outcome: nil, error: nil)
        payload = { state: state.to_s }
        if outcome
          payload[:result] = outcome.respond_to?(:err?) && outcome.err? ? "error" : "ok"
          payload[:category] = outcome.category.to_s if outcome.respond_to?(:category) && outcome.err?
        end
        payload[:error_class] = error.class.name if error
        append_event("coordinator_terminal", payload, run_id:)
      end

      # Bounded repair summary; no prompt, source text, or model output enters the
      # coordinator ledger. A failed write remains an error rather than a false
      # successful receipt.
      def record_repair_outcome(law:, status:, fixed:, breakdown:)
        counts = (breakdown || {}).to_h.to_h { |key, value| [key.to_s, Integer(value)] }
        append_event("repair_pass", {
          law: law.to_s, status: status.to_s, fixed: Integer(fixed), breakdown: counts
        }, run_id: Fiber[:master_fix_kernel_run_id])
      end

      def observe(path = @root, run_id: nil)
        observation = build_observation(path)
        row = append_event("observation", {
          command: observation.command,
          output: observation.output,
          hash: observation.hash
        }, run_id:)
        observation.with(seq: row.fetch("seq"))
      end

      # The repair callback proposes a path => replacement-text map. This
      # method records the exact diff and both sides' hashes before touching disk.
      def apply(repair)
        manifest = manifest_for(repair.target)
        require_access!(manifest, :write, run_id: repair.run_id, target: repair.target)
        current = build_observation(repair.target)
        unless current.hash == repair.observation_hash
          append_event("repair_rejected", {
            law: repair.law, reason: "observation changed before apply",
            expected_observation_hash: repair.observation_hash, actual_observation_hash: current.hash
          }, run_id: repair.run_id)
          raise "repair refused: observation changed before apply"
        end

        repair.changes.each do |change|
          absolute = safe_file_path(manifest.root, change.path, require_existing: true)
          current_hash = Digest::SHA256.file(absolute).hexdigest
          unless current_hash == change.before_hash
            append_event("repair_rejected", {
              law: repair.law, path: change.path, reason: "before hash mismatch",
              expected: change.before_hash, actual: current_hash
            }, run_id: repair.run_id)
            raise "repair refused: before hash mismatch for #{change.path}"
          end
        end

        append_event("repair", {
          law: repair.law,
          tree: repair.tree,
          target: relative(manifest.root, repair.target),
          observation_hash: repair.observation_hash,
          before_hash: repair.before_hash,
          after_hash: repair.after_hash,
          diff: repair.diff,
          changes: repair.changes.map do |change|
            { path: change.path, before_hash: change.before_hash, after_hash: change.after_hash }
          end
        }, run_id: repair.run_id)

        applied = []
        begin
          repair.changes.each do |change|
            absolute = safe_file_path(manifest.root, change.path, require_existing: true)
            atomic_replace(absolute, change.after_content, change.mode)
            applied << [absolute, change.before_content, change.mode]
          end
        rescue StandardError => error
          rollback_errors = []
          applied.reverse_each do |absolute, old_content, mode|
            begin
              atomic_replace(absolute, old_content, mode)
            rescue StandardError => rollback_error
              rollback_errors << "#{absolute}: #{rollback_error.message}"
            end
          end
          append_event("repair_failed", {
            law: repair.law, error: "#{error.class}: #{error.message}",
            rollback_errors: rollback_errors
          }, run_id: repair.run_id)
          raise "repair failed: #{error.message}#{rollback_errors.empty? ? '' : "; rollback failed: #{rollback_errors.join('; ')}"}"
        end

        repair
      end

      def verify(path, repair)
        observation = observe(path, run_id: repair.run_id)
        files_ok = repair.changes.all? do |change|
          observed = observation.file(change.path)
          observed && observed.hash == change.after_hash
        end
        append_event("verification", {
          law: repair.law,
          command: observation.command,
          output: observation.output,
          hash: observation.hash,
          expected_after_hash: repair.after_hash,
          ok: files_ok
        }, run_id: repair.run_id)
        files_ok
      end

      def fix(path = @root, max_iterations: 100, laws: @laws)
        target = resolve_path(path)
        run_id = SecureRandom.hex(12)
        append_event("run_started", {
          actor: @actor, target: target, max_iterations: Integer(max_iterations)
        }, run_id:)
        last_observation = nil
        last_repair = nil
        iterations = 0
        selected_laws = laws || default_laws

        while iterations < Integer(max_iterations)
          iterations += 1
          last_observation = observe(target, run_id:)
          firing_law = selected_laws.find do |law|
            result = law.check.call(last_observation)
            raise "law #{law.name} returned a non-boolean result" unless result == true || result == false

            result
          end

          unless firing_law
            append_event("terminal", { state: "converged", iterations: iterations }, run_id:)
            return Outcome.new(state: :converged, run_id:, iterations:, reason: "no law fires",
                               observation: last_observation, repair: last_repair)
          end

          if firing_law.sacred || !firing_law.automatic
            reason = firing_law.sacred ? "sacred law requires human decision" : "law repair is not automatic"
            append_event("escalation", { law: firing_law.name, reason: }, run_id:)
            append_event("terminal", { state: "escalated", law: firing_law.name, iterations: }, run_id:)
            return Outcome.new(state: :escalated, run_id:, iterations:, reason:, observation: last_observation,
                               repair: last_repair)
          end

          proposal = firing_law.repair.call(last_observation)
          raise "law #{firing_law.name} returned no repair" unless proposal.is_a?(Hash) && !proposal.empty?

          last_repair = prepare_repair(last_observation, target, firing_law, proposal, run_id)
          apply(last_repair)
          unless verify(target, last_repair)
            append_event("terminal", { state: "failed", law: firing_law.name,
                                       reason: "repair verification failed", iterations: }, run_id:)
            return Outcome.new(state: :failed, run_id:, iterations:, reason: "repair verification failed",
                               observation: last_observation, repair: last_repair)
          end
        end

        append_event("terminal", { state: "failed", iterations:,
                                   reason: "iteration limit reached" }, run_id:)
        Outcome.new(state: :failed, run_id:, iterations:, reason: "iteration limit reached",
                    observation: last_observation, repair: last_repair)
      rescue BoundaryViolation => error
        append_event("terminal", { state: "escalated", reason: error.message }, run_id:) if run_id
        Outcome.new(state: :escalated, run_id:, iterations:, reason: error.message,
                    observation: last_observation, repair: last_repair)
      rescue StandardError => error
        begin
          append_event("failure", { error: "#{error.class}: #{error.message}", iterations: }, run_id:) if run_id
          append_event("terminal", { state: "failed", reason: "#{error.class}: #{error.message}",
                                     iterations: }, run_id:) if run_id
        rescue StandardError
          # A corrupt ledger must remain untouched. The failure is still returned.
        end
        Outcome.new(state: :failed, run_id:, iterations:, reason: "#{error.class}: #{error.message}",
                    observation: last_observation, repair: last_repair)
      end

      def verify_log!
        self.class.read_log(@log_path)
      end

      def replay(seq)
        self.class.replay_events(root: @workspace_root, seq:)
      end

      def self.replay_events(root:, seq:)
        number = Integer(seq)
        raise ArgumentError, "sequence must be a positive integer" unless number.positive?

        path = File.join(locate_workspace_static(File.expand_path(root)), LOG_RELATIVE_PATH)
        events = read_log(path)
        selected = events.find { |row| row.fetch("seq") == number }
        return nil unless selected

        run_id = selected["run_id"]
        run_events = run_id ? events.select { |row| row["run_id"] == run_id } : [selected]
        { "sequence" => number, "run_id" => run_id, "events" => run_events }
      end

      def self.replay_cli(root:, seq:)
        unless seq && seq.match?(/\A[1-9][0-9]*\z/)
          warn "master0: usage master replay sequence"
          return 64
        end

        result = replay_events(root:, seq:)
        unless result
          warn "master0: replay sequence not found"
          return 1
        end

        puts JSON.pretty_generate(result)
        0
      rescue LedgerCorruption => error
        warn "master0: audit log corrupt, #{error.message}"
        1
      rescue StandardError => error
        warn "master0: replay failed, #{error.class}: #{error.message}"
        1
      end

      def self.read_log(path)
        return [] unless File.file?(path)

        File.open(path, "rb") { |file| read_log_io(file) }
      end

      def self.locate_workspace_static(path)
        cursor = path
        loop do
          return cursor if File.directory?(File.join(cursor, ".git")) || File.file?(File.join(cursor, ".git"))

          parent = File.dirname(cursor)
          return path if parent == cursor

          cursor = parent
        end
      end
      private_class_method :locate_workspace_static

      private

      def default_laws
        require_relative "../../laws"
        Master::Fix::Laws::LAWS
      end

      def locate_workspace(path)
        self.class.send(:locate_workspace_static, path)
      end

      def resolve_path(path)
        value = path.to_s
        absolute = File.expand_path(value.empty? ? @root : value, @workspace_root)
        root_real = File.realpath(@workspace_root)
        if File.exist?(absolute) || File.symlink?(absolute)
          ensure_within!(File.realpath(absolute), root_real)
        else
          parent_real = File.realpath(File.dirname(absolute))
          ensure_within!(parent_real, root_real)
        end
        absolute
      end

      def manifest_for(path)
        target = resolve_path(path)
        cursor = File.directory?(target) ? target : File.dirname(target)
        loop do
          candidate = File.join(cursor, MANIFEST)
          if File.file?(candidate) && !File.symlink?(candidate)
            data = YAML.safe_load_file(candidate, aliases: false)
            tree = data.fetch("tree").to_s
            raise "manifest tree #{tree} does not match directory #{File.basename(cursor).downcase}" unless tree == File.basename(cursor).downcase
            raise "manifest schema must be 1" unless data.fetch("schema") == 1

            allows = data.fetch("allows")
            raise "manifest allows must be a mapping" unless allows.is_a?(Hash)
            allows.each do |principal, access|
              raise "invalid access value for #{principal}" unless ACCESS.include?(access.to_s)
            end
            adapters = data.fetch("adapters", [])
            raise "manifest adapters must be paths" unless adapters.is_a?(Array) && adapters.all? { |value| value.is_a?(String) }
            adapters.each do |adapter|
              adapter_path = safe_repo_path(adapter)
              raise "manifest adapter missing: #{adapter}" unless File.file?(adapter_path) && !File.symlink?(adapter_path)
            end
            return Data.define(:root, :tree, :allows, :data).new(cursor, tree, allows.transform_keys(&:to_s), data)
          end

          parent = File.dirname(cursor)
          raise "no .pub4 boundary manifest for #{target}" if parent == cursor || !within?(parent, @workspace_root)

          cursor = parent
        end
      end

      def require_access!(manifest, needed, run_id: nil, target:)
        granted = manifest.allows.fetch(@actor, "none").to_s
        reads = %w[read read_write].include?(granted)
        writes = %w[write read_write].include?(granted)
        allowed = needed == :read ? reads : writes
        return true if allowed

        append_event("boundary_denied", {
          actor: @actor, tree: manifest.tree, target: relative(manifest.root, target),
          required: needed.to_s, granted:
        }, run_id:) if run_id
        raise BoundaryViolation.new(tree: manifest.tree, actor: @actor, required: needed,
                                    granted: granted)
      end

      def build_observation(path)
        target = resolve_path(path)
        raise "observation target is a symlink: #{target}" if File.symlink?(target)
        manifest = manifest_for(target)
        require_access!(manifest, :read, target:)
        ensure_within!(target, manifest.root)
        scope = relative(manifest.root, target)
        files = collect_files(target, manifest.root)
        changes = git_changes(target, manifest.root)
        sacred_paths = load_sacred_paths(manifest.tree)
        entries = files.values.sort_by(&:path).map do |file|
          { path: file.path, hash: file.hash, bytes: file.bytes, kind: file.kind, mode: file.mode }
        end
        payload = {
          tree: manifest.tree, scope:, files: entries,
          deleted: changes.fetch(:deleted), modified: changes.fetch(:modified)
        }
        output = JSON.generate(payload)
        command = "snapshot #{manifest.tree}#{scope.empty? ? '' : " #{scope}"}"
        Observation.new(command:, output:, hash: Digest::SHA256.hexdigest(output), files:,
                        deleted_paths: changes.fetch(:deleted), modified_paths: changes.fetch(:modified),
                        tree: manifest.tree, scope:, manifest_root: manifest.root,
                        sacred_paths:, seq: nil)
      end

      def collect_files(target, manifest_root)
        files = {}
        add_file = lambda do |path|
          rel = relative(manifest_root, path)
          if File.symlink?(path)
            link = File.readlink(path)
            stat = File.lstat(path)
            digest = Digest::SHA256.hexdigest("symlink:" + link)
            files[rel] = FileState.new(path: rel, content: nil, hash: digest, bytes: link.bytesize,
                                       kind: "symlink", mode: stat.mode & 0o777)
            next
          end

          stat = File.stat(path)
          return unless stat.file?
          bytes = stat.size
          digest = Digest::SHA256.file(path).hexdigest
          content = nil
          binary = false
          if bytes <= MAX_TEXT_BYTES
            raw = File.binread(path)
            binary = raw.include?("\0")
            unless binary
              candidate = raw.dup.force_encoding(Encoding::UTF_8)
              content = candidate if candidate.valid_encoding?
            end
          end
          files[rel] = FileState.new(path: rel, content:, hash: digest, bytes:,
                                     kind: binary ? "binary" : "file", mode: stat.mode & 0o777)
        rescue Errno::ENOENT, Errno::EACCES
          raise "file changed during observation: #{path}"
        end

        if File.file?(target)
          add_file.call(target)
        elsif File.directory?(target)
          stack = [target]
          until stack.empty?
            directory = stack.pop
            Dir.children(directory).sort.reverse_each do |name|
              path = File.join(directory, name)
              if File.symlink?(path)
                add_file.call(path)
              elsif File.directory?(path)
                next if IGNORED_DIRECTORIES.include?(name)

                stack << path
              elsif File.file?(path)
                add_file.call(path)
              end
            end
          end
        end
        files
      end

      def git_changes(target, manifest_root)
        return { deleted: [], modified: [] } unless File.directory?(File.join(@workspace_root, ".git")) ||
                                                        File.file?(File.join(@workspace_root, ".git"))

        target_relative = relative(@workspace_root, target)
        output, error, status = Master::Io::Exec.capture3(
          "git", "-C", @workspace_root, "diff", "--name-status", "-z", "--no-renames", "HEAD", "--",
          target_relative.empty? ? "." : target_relative
        )
        raise "git change inventory failed: #{error.to_s.strip}" unless status.success?

        parts = output.split("\0")
        deleted = []
        modified = []
        until parts.empty?
          status_code = parts.shift
          changed_path = parts.shift
          next unless changed_path

          tree_path = relative(manifest_root, File.join(@workspace_root, changed_path))
          if status_code.start_with?("D")
            deleted << tree_path
          elsif %w[M A T].any? { |code| status_code.start_with?(code) }
            modified << tree_path
          end
        end
        { deleted: deleted.uniq.sort, modified: modified.uniq.sort }
      rescue Errno::ENOENT => error
        raise "cannot observe Git state: #{error.message}"
      end

      def load_sacred_paths(tree)
        return [] unless tree == "master"

        path = File.join(manifest_for(File.join(@workspace_root, "MASTER")).root, "data", "soul.yml")
        source = tracked_soul(path) || File.read(path)
        data = YAML.safe_load(source, aliases: false)
        Array(data.dig("absolute", "sacred_paths")).map(&:to_s)
      rescue StandardError
        # Failure to load the constitutional path list is fail-closed: a sentinel
        # matches every path in the tree, so the sacred law escalates.
        ["*"]
      end

      def tracked_soul(path)
        return unless File.directory?(File.join(@workspace_root, ".git")) || File.file?(File.join(@workspace_root, ".git"))

        relative_path = relative(@workspace_root, path)
        output, _error, status = Master::Io::Exec.capture3("git", "-C", @workspace_root, "show", "HEAD:#{relative_path}")
        status.success? ? output : nil
      end

      def prepare_repair(observation, target, law, proposal, run_id)
        manifest = manifest_for(target)
        changes = proposal.map do |raw_path, replacement|
          raise "law #{law.name} proposed a non-string path" unless raw_path.is_a?(String)
          raise "law #{law.name} proposed a non-text replacement" unless replacement.is_a?(String)
          raise "law #{law.name} proposed invalid UTF-8" unless replacement.dup.force_encoding(Encoding::UTF_8).valid_encoding?
          raise "law #{law.name} proposed an empty path" if raw_path.empty?
          raise "law #{law.name} proposed a control character in a path" if raw_path.match?(/[\x00-\x1f\x7f]/)

          file = observation.file(raw_path)
          raise "law #{law.name} targeted an unobserved or binary file: #{raw_path}" unless file && file.content
          absolute = safe_file_path(manifest.root, raw_path, require_existing: true)
          ensure_within!(absolute, target)
          before = File.binread(absolute)
          before_hash = Digest::SHA256.hexdigest(before)
          raise "observation stale for #{raw_path}" unless before_hash == file.hash
          after_hash = Digest::SHA256.hexdigest(replacement.b)
          raise "law #{law.name} proposed a no-op for #{raw_path}" if before_hash == after_hash

          diff = unified_diff(raw_path, before, replacement)
          Change.new(path: raw_path, before_hash:, after_hash:, before_content: before,
                     after_content: replacement, diff:, mode: file.mode)
        end
        raise "law #{law.name} proposed duplicate paths" unless changes.map(&:path).uniq.size == changes.size
        changes.sort_by!(&:path)
        before_hash = Digest::SHA256.hexdigest(JSON.generate(changes.map { |change| [change.path, change.before_hash] }))
        after_hash = Digest::SHA256.hexdigest(JSON.generate(changes.map { |change| [change.path, change.after_hash] }))
        Repair.new(law: law.name.to_s, target:, tree: observation.tree,
                   observation_hash: observation.hash, before_hash:, after_hash:,
                   diff: changes.map(&:diff).join("\n"), changes:, run_id:)
      end

      def unified_diff(path, before, after)
        Tempfile.create(["pub4-before-", ".txt"]) do |old_file|
          Tempfile.create(["pub4-after-", ".txt"]) do |new_file|
            old_file.binmode
            new_file.binmode
            old_file.write(before)
            new_file.write(after)
            old_file.flush
            new_file.flush
            output, error, status = Master::Io::Exec.capture3(
              "diff", "-u", "-L", "a/#{path}", "-L", "b/#{path}", old_file.path, new_file.path
            )
            raise "diff failed: #{error.to_s.strip}" if status.exitstatus && status.exitstatus > 1
            raise "diff produced no change for #{path}" if status.success? || output.empty?

            output
          end
        end
      end

      def safe_file_path(base, relative_path, require_existing:)
        relative_path = relative_path.to_s
        raise "unsafe relative path" if relative_path.empty? || relative_path.start_with?("/", "\\") ||
                                        relative_path.match?(/\A[A-Za-z]:/) ||
                                        relative_path.split(/[\\\/]/).include?("..") ||
                                        relative_path.match?(/[\x00-\x1f\x7f]/)
        absolute = File.expand_path(relative_path, base)
        ensure_within!(absolute, base)
        raise "symlink repair target refused: #{relative_path}" if File.symlink?(absolute)
        raise "repair target is missing: #{relative_path}" if require_existing && !File.file?(absolute)

        real_parent = File.realpath(File.dirname(absolute))
        ensure_within!(real_parent, File.realpath(base))
        absolute
      end

      def atomic_replace(path, content, mode)
        raise "refusing to replace a symlink" if File.symlink?(path)

        Tempfile.create([".pub4-repair-", ".tmp"], File.dirname(path)) do |file|
          file.binmode
          file.write(content)
          file.flush
          file.fsync
          file.chmod(mode)
          File.rename(file.path, path)
        end
        true
      end

      def append_event(kind, payload, run_id: nil)
        FileUtils.mkdir_p(File.dirname(@log_path), mode: 0o700)
        File.open(@log_path, File::RDWR | File::CREAT, 0o600) do |file|
          file.flock(File::LOCK_EX)
          head = append_head(file)
          body = {
            "seq" => head.fetch(:seq) + 1,
            "at" => Time.now.utc.iso8601(6),
            "run_id" => run_id,
            "kind" => kind.to_s,
            "payload" => payload,
            "prev" => head.fetch(:hash)
          }
          row = body.merge("hash" => Digest::SHA256.hexdigest(JSON.generate(body)))
          line = JSON.generate(row) + "\n"
          file.seek(0, IO::SEEK_END)
          written = file.write(line)
          raise IOError, "ledger append wrote #{written || 0} of #{line.bytesize} bytes" unless written == line.bytesize

          file.flush
          file.fsync
          cache_log_head(file, row.fetch("seq"), row.fetch("hash"))
          row
        ensure
          file.flock(File::LOCK_UN) rescue nil
        end
      end

      def append_head(file)
        stat = file.stat
        cached = @log_head
        if cached
          unless stat.dev == cached.fetch(:dev) && stat.ino == cached.fetch(:ino) &&
                 stat.size >= cached.fetch(:size)
            raise LedgerCorruption, "ledger identity changed or ledger was truncated"
          end

          if stat.size > cached.fetch(:size)
            suffix = self.class.read_log_suffix(file, cached)
            return cache_log_head(file, suffix.fetch(:seq), suffix.fetch(:hash))
          end

          return cached if stat.mtime == cached.fetch(:mtime) && stat.ctime == cached.fetch(:ctime)
        end

        events = self.class.read_log_io(file)
        last = events.last
        cache_log_head(file, last ? last.fetch("seq") : 0, last ? last.fetch("hash") : GENESIS)
      end

      def cache_log_head(file, seq, hash)
        stat = file.stat
        @log_head = {
          dev: stat.dev,
          ino: stat.ino,
          size: stat.size,
          mtime: stat.mtime,
          ctime: stat.ctime,
          seq:,
          hash:
        }
      end

      # Validate records appended after a previously verified byte offset. The
      # file flock in append_event serializes writers; the cached offset lets a
      # long /fix run validate each new record once instead of rescanning its
      # complete hash chain before every append.
      def self.read_log_suffix(file, head)
        previous = head.fetch(:hash)
        expected_seq = head.fetch(:seq) + 1
        file.seek(head.fetch(:size), IO::SEEK_SET)
        file.each_line do |line|
          begin
            raise LedgerCorruption, "sequence #{expected_seq}: incomplete final record" unless line.end_with?("\n")
            next if line.strip.empty?

            row = JSON.parse(line)
            body = row.reject { |key, _| key == "hash" }
            raise LedgerCorruption, "sequence #{expected_seq}: sequence gap" unless row.fetch("seq") == expected_seq
            raise LedgerCorruption, "sequence #{expected_seq}: previous hash mismatch" unless row.fetch("prev") == previous
            actual = Digest::SHA256.hexdigest(JSON.generate(body))
            raise LedgerCorruption, "sequence #{expected_seq}: event hash mismatch" unless actual == row.fetch("hash")

            previous = row.fetch("hash")
            expected_seq += 1
          rescue JSON::ParserError, KeyError, TypeError, NoMethodError => error
            raise LedgerCorruption, "sequence #{expected_seq}: #{error.message}"
          end
        end
        { seq: expected_seq - 1, hash: previous }
      end

      # Full-chain verification remains the explicit audit/replay path and is
      # also the initialization path for a process with no trusted head cache.
      def self.read_log_io(file)
        previous = GENESIS
        expected_seq = 1
        events = []
        file.rewind
        file.each_line.with_index(1) do |line, line_number|
          begin
            raise LedgerCorruption, "line #{line_number}: incomplete final record" unless line.end_with?("\n")
            next if line.strip.empty?

            row = JSON.parse(line)
            body = row.reject { |key, _| key == "hash" }
            raise LedgerCorruption, "line #{line_number}: sequence gap" unless row.fetch("seq") == expected_seq
            raise LedgerCorruption, "line #{line_number}: previous hash mismatch" unless row.fetch("prev") == previous
            actual = Digest::SHA256.hexdigest(JSON.generate(body))
            raise LedgerCorruption, "line #{line_number}: event hash mismatch" unless actual == row.fetch("hash")

            events << row
            previous = row.fetch("hash")
            expected_seq += 1
          rescue JSON::ParserError, KeyError, TypeError, NoMethodError => error
            raise LedgerCorruption, "line #{line_number}: #{error.message}"
          end
        end
        events
      end

      def relative(base, path)
        value = File.expand_path(path.to_s)
        prefix = File.expand_path(base) + File::SEPARATOR
        return "" if value == File.expand_path(base)
        raise "path escapes boundary: #{path}" unless value.start_with?(prefix)

        value.delete_prefix(prefix)
      end

      def safe_repo_path(path)
        safe_file_path(@workspace_root, path, require_existing: false)
      end

      def ensure_within!(path, base)
        raise "path escapes boundary: #{path}" unless within?(path, base)

        true
      end

      def within?(path, base)
        value = File.expand_path(path)
        root = File.expand_path(base)
        value == root || value.start_with?(root + File::SEPARATOR)
      end
    end
  end
end
