# frozen_string_literal: true

require "fileutils"
require "json"
require "yaml"
require "time"
require_relative "change_scope"
require_relative "severity"
require_relative "priority"
require_relative "../trace/log"

module Master
  module Fix
    class ConflictResolver
      LOG_PATH = "runtime/conflict_log.jsonl"
      # Append-only with no cap previously ran unbounded -- reached 890MB
      # alongside activity.jsonl's 1.2GB, together filling the disk and
      # crashing an in-progress /fix round. Same rotate-not-truncate fix.
      LOG_MAX_BYTES = 25 * 1024 * 1024
      # How many rotated generations (.1, .2, ...) to keep before the oldest
      # is discarded, so a slow-burn conflict-heavy period doesn't just move
      # the unbounded-growth problem from one file to an unbounded set of them.
      LOG_GENERATIONS = 3
      DRY_LAWS = %w[DRY duplicate_code].freeze
      WET_AHA = "WET/AHA".freeze
      DUPLICATION_THRESHOLD = 3

      def initialize(root:, bus: nil, config: nil, law_resolver: nil)
        @root = root
        @bus = bus
        @config = config || load_config
        @law_resolver = law_resolver || Ground::LawResolver.new
        @laws_index = Priority.laws_index(root: @root)
      end

      def filter_findings(findings)
        rows = merge_equivalents(findings.map { |finding| normalize(finding) })
        suppress_dry_below_law_of_three(rows).then { |kept| suppress_lower_priority_laws(kept) }
      end

      EQUIVALENTS_FILE = File.expand_path("../../data/finding_equivalents.yml", __dir__)

      # Alias ("rubocop:Layout/LineLength") => canonical law ("LONG_LINE"), from data/finding_equivalents.yml.
      def self.equivalents
        @equivalents ||= begin
          table = YAML.safe_load_file(EQUIVALENTS_FILE) || {}
          table.flat_map { |law, aliases| Array(aliases).map { |name| [name.to_s, law.to_s] } }.to_h.freeze
        end
      end

      # One problem reported by two instruments on one line is one finding: the canonical law is
      # kept, with the others listed on it as also:, so the repair is decided and asked for once.
      def merge_equivalents(rows)
        groups = rows.group_by { |row| [row["file"] || row["path"], row["line"], canonical_law(row)] }
        groups.flat_map { |(*, law), group| group.size == 1 || law.nil? ? group : [merged(group, law)] }
      end

      def merged(group, law)
        kept = group.find { |row| row["law"].to_s == law } || group.first
        kept.merge("also" => (group - [kept]).map { |row| alias_name(row) })
      end

      def canonical_law(row)
        name = alias_name(row)
        table = self.class.equivalents
        table.fetch(name) { table.value?(name) ? name : nil }
      end

      def alias_name(row)
        law = row["law"].to_s
        return law unless %w[rubocop reek].include?(law)

        rule = row["message"].to_s[%r{\A(?:rubocop: |reek: )?([A-Z]\w+(?:/\w+)?)}, 1]
        "#{law}:#{rule}"
      end

      # Would applying this fix trade the original violation for a worse one?
      # The finding that made the last reject_higher_priority? answer true, for the log line.
      attr_reader :last_blocker

      def reject_higher_priority?(original_violation:, before:, after:, path:)
        baseline = priority_of(original_violation)
        blocker = findings_introduced(before:, after:, path:).find do |finding|
          Priority.higher?(priority_of(finding), baseline)
        end
        @last_blocker = blocker
        return false unless blocker

        log_conflict(
          law_a: baseline[:law_id],
          law_b: blocker["law"],
          resolution: "reject fix: introduced higher-priority #{blocker["severity"]} finding",
          file: path,
          line: blocker["line"],
        )
        true
      end

      private

      # Priority tuple for either shape this class sees: an original violation
      # (symbol *or* string keys, hence the double lookup) or a normalized
      # finding (string keys only).
      def priority_of(row)
        {
          law_id: (row[:law] || row["law"]).to_s,
          severity: (row[:severity] || row["severity"]).to_s.to_sym,
          law_resolver: @law_resolver,
          laws_index: @laws_index,
        }
      end

      # The repair loop's own definition of a new finding (ChangeScope.introduced_findings), so
      # the priority check and boyscout never disagree about what a change introduced.
      def findings_introduced(before:, after:, path:)
        stamped = ->(rows) { rows.map { |finding| normalize(finding).merge("file" => path) } }
        ChangeScope.introduced_findings(stamped.call(before), stamped.call(after))
      end

      attr_reader :root, :bus, :config

      def suppress_dry_below_law_of_three(rows)
        dry_rows = rows.select { |finding| DRY_LAWS.include?(finding["law"]) }
        return rows unless dry_rows.any? && dry_rows.size < DUPLICATION_THRESHOLD

        dry_rows.each do |finding|
          log_conflict(
            law_a: finding["law"],
            law_b: WET_AHA,
            resolution: "favor WET/AHA below three duplications",
            file: finding["file"],
            line: finding["line"],
          )
        end
        rows - dry_rows
      end

      # The losers are gathered first and dropped in one pass: subtracting each group's losers from
      # every row in turn took 18s over a 28,000-finding MASTER scan, and a report runs this per render.
      def suppress_lower_priority_laws(rows)
        losers = rows.group_by { |finding| [finding["file"], finding["line"]] }.values.flat_map do |group|
          next [] if group.size < 2

          winner = pick_group_winner(group)
          group.reject { |finding| finding == winner }
        end
        return rows if losers.empty?

        dropped = losers.to_set
        rows.reject { |finding| dropped.include?(finding) }
      end

      def pick_group_winner(group)
        group.reduce(group.first) { |best, finding| resolve_pair(best, finding) }
      end

      def resolve_pair(best, finding)
        favored = @law_resolver.winner(best["law"], finding["law"], laws_index: @laws_index)
        if favored == best["law"]
          log_conflict(law_a: best["law"], law_b: finding["law"],
            resolution: "law priority favors #{best["law"]}", file: finding["file"], line: finding["line"])
          best
        else
          log_conflict(law_a: finding["law"], law_b: best["law"],
            resolution: "law priority favors #{finding["law"]}", file: best["file"], line: best["line"])
          finding
        end
      end

      def log_conflict(law_a:, law_b:, resolution:, file:, line:)
        payload = {
          timestamp: Time.now.utc.iso8601,
          strategy: config.fetch("strategy", "highest_priority_wins"),
          prompt_user: config.fetch("prompt_user", false),
          law_a: law_a.to_s,
          law_b: law_b.to_s,
          resolution: resolution.to_s,
          file: file.to_s,
          line: line.to_i,
        }
        directory = File.dirname(log_path)
        FileUtils.mkdir_p(directory)
        line = JSON.generate(payload) + "\n"
        raise ArgumentError, "conflict record exceeds log cap" if line.bytesize >= LOG_MAX_BYTES

        lock_path = "#{log_path}.lock"
        raise IOError, "conflict log lock is a symlink" if File.symlink?(lock_path)
        File.open(lock_path, File::RDWR | File::CREAT, 0o600) do |lock|
          File.chmod(0o600, lock_path)
          lock.flock(File::LOCK_EX)
          raise IOError, "conflict log is a symlink" if File.symlink?(log_path)
          File.chmod(0o600, log_path) if File.file?(log_path)

          rotate_log_if_oversized!(threshold: LOG_MAX_BYTES - line.bytesize)
          size = File.file?(log_path) ? File.size(log_path) : 0
          raise IOError, "conflict log rotation failed to honor byte cap" if size + line.bytesize > LOG_MAX_BYTES

          File.open(log_path, File::WRONLY | File::CREAT | File::APPEND, 0o600) do |io|
            io.write(line)
            io.flush
            io.fsync
          end
        ensure
          lock.flock(File::LOCK_UN) if lock
        end
        bus&.publish("conflict:resolved", payload)
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "conflict_resolver.log", event_bus: bus)
      end

      def normalize(finding)
        hash = finding.respond_to?(:to_h) ? finding.to_h : finding
        hash.each_with_object({}) { |(key, value), out| out[key.to_s] = value }
      end

      def log_path
        File.join(root, LOG_PATH)
      end

      def rotate_log_if_oversized!(threshold: LOG_MAX_BYTES)
        return unless File.file?(log_path) && File.size(log_path) > threshold

        oldest = "#{log_path}.#{LOG_GENERATIONS}"
        File.delete(oldest) if File.exist?(oldest)
        (LOG_GENERATIONS - 1).downto(1) do |i|
          src = "#{log_path}.#{i}"
          File.rename(src, "#{log_path}.#{i + 1}") if File.exist?(src)
        end
        File.rename(log_path, "#{log_path}.1")
        (1..LOG_GENERATIONS).each do |generation|
          Master::Trace::Log.compact_rotated("#{log_path}.#{generation}", LOG_MAX_BYTES)
        end
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "ConflictResolver.rotate_log_if_oversized")
      end

      def load_config
        soul = Master.soul_config(root: @root)
        soul.dig("negotiable", "conflict_resolution") || {}
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "ConflictResolver.load_config")
        {}
      end
    end
  end
end
