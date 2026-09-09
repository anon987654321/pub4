# frozen_string_literal: true

require "open3"

module Master
  module Ground
    module Orders
      # Standing-order callables. Subclass and implement `call`. Returning a
      # Master::Result::Ok marks the order done; Result::Err marks it errored.
      class Base
        def initialize(container:)
          @container = container
        end

        def bus = @container[:bus]
        def root = @container[:root]
        def event = @container[:event]

        def call
          raise NotImplementedError, "#{self.class}#call not implemented"
        end
      end

      # After every source write, emit merge/rename targets — OpenBSD-flat, dense parameterized slugs.
      class AggressiveMerge < Base
        THIN_LINES = 45
        MAX_LIB_DEPTH = 4

        def call
          paths = mutation_paths
          candidates = paths.flat_map { |path| candidates_for(path) }
                            .uniq { |row| "#{row[:action]}:#{row[:from]}:#{row[:to]}" }
          candidates.each { |row| bus&.publish("aggressive_merge:candidate", **row) }
          bus&.publish("aggressive_merge:scan", count: candidates.size, paths: paths.size)
          Result.ok(candidates:, paths:)
        rescue StandardError => e
          Result.err(e.message)
        end

        private

        def mutation_paths
          tracker = Master::Trace::WriteTracker.current
          touched = Array(tracker&.paths).map { |path| expand_path(path) }.reject(&:empty?).uniq
          return touched if touched.any?

          event_path = @container[:event]&.dig(:path).to_s
          expanded = expand_path(event_path)
          if !expanded.empty? && File.exist?(expanded)
            return [expanded]
          elsif !expanded.empty?
            parent = File.dirname(expanded)
            return [parent] if File.directory?(parent)
          end

          lib = File.join(root, "lib")
          File.directory?(lib) ? [lib] : [root]
        end

        def expand_path(path)
          value = path.to_s.strip
          return "" if value.empty?

          full = File.expand_path(value, root)
          full.start_with?("#{root}/") ? full : ""
        rescue StandardError
          ""
        end

        def candidates_for(path)
          full = expand_path(path)
          return [] if full.empty?

          if File.file?(full)
            file_candidates(full) + directory_candidates(File.dirname(full))
          elsif File.directory?(full)
            directory_candidates(full)
          else
            []
          end
        end

        def file_candidates(path)
          rel = rel_path(path)
          return [] unless rel.end_with?(".rb")

          out = slug_candidates(rel, File.basename(path, ".rb"))
          lines = File.foreach(path).count
          if lines.positive? && lines <= THIN_LINES
            target = fold_target_for(path)
            out << action(:merge, rel, target, "thin file (#{lines} lines) — fold into parent") if target
          end

          if rel.start_with?("lib/") && rel.count("/") > MAX_LIB_DEPTH
            out << action(:flatten, rel, shallow_target(rel), "depth #{rel.count('/')} > #{MAX_LIB_DEPTH} — flatten toward lib/")
          end
          out.uniq { |row| "#{row[:action]}:#{row[:from]}:#{row[:to]}" }
        rescue StandardError => e
          Master::Ground::Swallow.log(e, context: "AggressiveMerge.file_candidates")
          []
        end

        def slug_candidates(rel, stem)
          ParameterizedSlug.issues_for_stem(stem).map do |issue|
            to_rel = issue.to == issue.from ? rel : rel.sub(/[^\/]+\.rb\z/, "#{issue.to}.rb")
            action(issue.action.to_sym, rel, to_rel, issue.reason)
          end
        end

        def directory_candidates(dir)
          return [] unless File.directory?(dir)

          Dir.glob(File.join(dir, "*.rb")).flat_map { |file| file_candidates(file) }
        end

        def fold_target_for(path)
          dir = File.dirname(path)
          stem = File.basename(path, ".rb")
          return if ParameterizedSlug.fold_suffix?(stem)

          siblings = Dir.glob(File.join(dir, "*.rb")).reject { |entry| entry == path }
          parent = siblings.find { |entry| File.basename(entry, ".rb") == stem.split("_").first }
          rel_path(parent) if parent
        end

        def shallow_target(rel)
          parts = rel.split("/")
          return rel if parts.size <= MAX_LIB_DEPTH + 1

          ["lib", parts[-2], parts[-1]].join("/")
        end

        def action(kind, from, to, reason)
          { action: kind.to_s, from: from.to_s, to: to.to_s, reason: reason.to_s }
        end

        def rel_path(path)
          path.delete_prefix("#{root}/")
        end
      end

      # Weekly review of data/* shape misfit. Walks every yaml under data/, flags
      # files that grew past LINE_LIMIT (split candidate), files with overlapping
      # top-level keys (merge candidate), and emits suggestions to the bus.
      class ArchitectureAudit < Base
        LINE_LIMIT = 200

        def call
          data_dir = File.join(root, "data")
          bloated = bloated_files(data_dir)
          overlaps = overlapping_keys(data_dir)
          bus&.publish("architecture_audit:bloated", files: bloated)
          bus&.publish("architecture_audit:overlap", pairs: overlaps)
          Result.ok(bloated:, overlaps:)
        rescue StandardError => e
          Result.err(e.message)
        end

        private

        def bloated_files(dir)
          Dir.glob(File.join(dir, "*.yml")).filter_map do |f|
            lines = File.foreach(f).count
            [File.basename(f), lines] if lines > LINE_LIMIT
          end.sort_by { |_, n| -n }
        end

        def overlapping_keys(dir)
          files = Dir.glob(File.join(dir, "*.yml"))
          keys = files.each_with_object({}) do |f, h|
            document = begin
              Master.load_yaml(f)
            rescue StandardError => e
              Master::Ground::Swallow.log(e, context: "architecture_audit.overlapping_keys", path: f)
              nil
            end
            h[File.basename(f)] = document.is_a?(Hash) ? document.keys : []
          end
          pairs = []
          keys.to_a.combination(2) do |(a, ka), (b, kb)|
            shared = ka & kb
            pairs << [a, b, shared] if shared.any?
          end
          pairs
        end
      end

      class Autocommit < Base
        def call
          repo = File.expand_path(File.join(root, ".."))
          out, _, status = Master::Io::Exec.capture3("git", "-C", repo, "status", "--porcelain")
          return Result.ok(skipped: true) unless status.success? && !out.strip.empty?
          commit_message = "auto: standing-order commit (#{out.lines.size} file(s))"
          _, st = Master::Io::Exec.capture2e("git", "-C", repo, "commit", "-m", commit_message)
          return Result.err("commit failed") unless st.success?
          if push_st.success?
            bus&.publish("autocommit:pushed", files: out.lines.size)
            Result.ok(committed: true, pushed: true)
          else
            bus&.publish("autocommit:push_failed", error: push_out.strip[0, 200])
            Result.ok(committed: true, pushed: false, push_error: push_out.strip)
          end
        rescue StandardError => e
          Result.err(e.message)
        end
      end

    # Backup — openrsync standing order.
    # Syncs ~/pub4 to wingman1.openbsd.amsterdam:backup using openrsync over SSH.
    # Runs as a background standing order; never blocks the main loop.
      class Backup < Base
        REMOTE_HOST = "s4vm23@wingman1.openbsd.amsterdam"
        REMOTE_PATH = "backup"
        SSH_OPTS = %w[-o BatchMode=yes -o ConnectTimeout=10].freeze

        # The repo root is one level above MASTER. This was "../../..", which
        # climbed three and landed outside the checkout entirely (/home on the
        # VPS), so the order would have rsynced the wrong tree to the remote.
        # Named so the path is assertable without executing the sync.
        def source_root = File.expand_path("..", root)

        def call
          src = source_root
          return Result.err("backup: #{src} is not a directory", category: :infrastructure) unless File.directory?(src)

          cmd = ["openrsync", "-ae", "ssh #{SSH_OPTS.join(" ")}",
                 src, "#{REMOTE_HOST}:#{REMOTE_PATH}"]
          out, status = Master::Io::Exec.capture2e(*cmd)
          if status.success?
            bus&.publish("backup:ok", src:)
            Result.ok("backup: synced #{File.basename(src)} → #{REMOTE_HOST}")
          else
            bus&.publish("backup:error", error: out.lines.last.to_s.strip)
            Result.err("backup: #{out.lines.last.to_s.strip}", category: :infrastructure)
          end
        rescue StandardError => e
          Master::Ground::Swallow.log(e, context: "Orders::Backup.call", event_bus: bus)
          Result.err(e.message, category: :infrastructure)
        end
      end

      # Continuous self-audit: scans lib/ against the axioms and reports drift.
      class ConstitutionDrift < Base
        STATE_PATH = "runtime/constitution_drift.json"

        def call
          scanner = @container[:scanner]
          return Result.err("no scanner in container") unless scanner

          report = build_report(scanner)
          publish_drift(report)
          persist(report)
          Result.ok(report)
        rescue StandardError => e
          Result.err(e.message)
        end

        private

        # total, delta-since-last-run, and per-axiom counts.
        def build_report(scanner)
          by_axiom = tally_violations(scanner)
          total = by_axiom.values.sum
          delta = total - load_previous[:total].to_i
          { total:, delta:, by_axiom:, worst: by_axiom.max_by { |_, n| n }&.first }
        end

        def lib_files
          Dir.glob(File.join(root, "lib", "**", "*.rb"))
             .reject { |p| p.include?("/knowledge/") || p.include?("/vendor/") }
             .sort
        end

        # axiom_tag => violation count, across all of lib/.
        def tally_violations(scanner)
          lib_files.each_with_object(Hash.new(0)) do |path, acc|
            result = scanner.scan(path, depth: :deep)
            next unless result.ok?
            result.value!.each { |f| Array(f[:tags]).each { |t| acc[t.to_s] += 1 } }
          end
        end

        # improved | regressed | steady — caught the moment a defect lands.
        def publish_drift(report)
          delta = report[:delta]
          kind = if delta.negative?
"improved"
else
(delta.positive? ? "regressed" : "steady")
end
          bus&.publish("constitution_drift:#{kind}", **report)
        end

        def state_file = File.join(root, STATE_PATH)

        def load_previous
          return { total: 0 } unless File.exist?(state_file)

          JSON.parse(File.read(state_file), symbolize_names: true)
        rescue StandardError => e
          Swallow.log(e, context: "constitution_drift.load_previous", event_bus: bus)
          { total: 0 }
        end

        def persist(report)
          FileUtils.mkdir_p(File.dirname(state_file))
          record = report.slice(:total, :by_axiom).merge(at: Time.now.utc.iso8601)
          File.write(state_file, JSON.pretty_generate(record))
        rescue StandardError => e
          Swallow.log(e, context: "constitution_drift.persist", event_bus: bus)
        end
      end

      class RestartMaster < Base
        def call
          _, status = Master::Io::Exec.capture2e("doas", "rcctl", "restart", "master")
          status.success? ? Result.ok(restarted: true) : Result.err("rcctl restart failed")
        rescue StandardError => e
          Result.err(e.message)
        end
      end

      # Maps standing-order callable: keys to Order subclasses. Decouples the yaml
      # from class names — `callable: autocommit` is stable even if the class moves.
      module Registry
        def self.lookup(key)
          table[key.to_s]
        end

        def self.table
          @table ||= {
            "autocommit" => Autocommit,
            "restart_master" => RestartMaster,
            "architecture_audit" => ArchitectureAudit,
            "aggressive_merge" => AggressiveMerge,
            "constitution_drift" => ConstitutionDrift,
            "backup" => Backup,
          }
        end

        def self.register(key, klass)
          table[key.to_s] = klass
        end
      end
    end
  end
end
