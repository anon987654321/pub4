# frozen_string_literal: true

require "digest"
require "set"

module Master
  module Fix
    # Turns correlated structural findings into bounded repair problems.
    #
    # A finding is an observation; a problem is the smallest connected set of
    # observations that can plausibly be solved by one structural operation.
    # Keeping the graph bounded prevents one noisy cross-file relation from
    # turning the whole tree into a single model call.
    class ProblemGraph
      MAX_FINDINGS = 24
      MAX_FILES = 12

      LAW_OPERATIONS = {
        "DEAD_SUBTREE" => "defragment",
        "PARALLEL_HIERARCHY" => "merge",
        "CYCLIC_DEPENDENCY" => "decouple",
        "FILE_SPRAWL" => "flatten",
        "NO_GOD_CLASS" => "split",
        "SMALL_FILES" => "split",
        "JS_MODULE_SIZE" => "split",
        "STALE_PATH_REFERENCE" => "rename",
        "PROSE_DUPLICATION" => "merge",
        "COMMAND_SURFACE_DUPLICATION" => "merge",
      }.freeze

      OPERATION_ALTERNATIVES = {
        "defragment" => %w[defragment merge relocate simplify],
        "decouple" => %w[decouple split relocate simplify],
        "flatten" => %w[flatten merge remove simplify],
        "merge" => %w[merge defragment flatten simplify],
        "split" => %w[split decouple relocate simplify],
        "relocate" => %w[relocate defragment flatten rename],
        "rename" => %w[rename relocate simplify],
        "reorder" => %w[reorder reflow simplify],
        "remove" => %w[remove defragment flatten simplify],
        "reflow" => %w[reflow reorder simplify],
        "simplify" => %w[simplify flatten remove merge],
        "recommend" => %w[recommend],
      }.freeze

      Problem = Data.define(
        :id, :findings, :files, :primary_operations, :candidate_operations,
        :confidence, :reason
      ) do
        def primary_operation = primary_operations.first.to_s

        def laws = findings.map { |_path, law, _message, _related| law }.uniq

        def size = findings.size

        def multi_signal? = laws.size > 1
      end

      def initialize(plan:)
        @plan = plan
      end

      def call(findings)
        rows = Array(findings).filter_map { |row| normalize(row) }
        return [] if rows.empty?

        components(rows).map { |group| problem(group) }
          .sort_by { |item| [operation_position(item.primary_operation), -item.size, item.id] }
      end

      private

      def normalize(row)
        path, law, message, related = Array(row)
        path = path.to_s
        law = law.to_s
        return if path.empty? || law.empty?

        impacted = [path, *Array(related)].map(&:to_s).reject(&:empty?).uniq.first(MAX_FILES)
        [path, law, message.to_s, impacted]
      end

      def components(rows)
        pending = rows.dup
        groups = []

        until pending.empty?
          seed = pending.shift
          group = [seed]

          loop do
            additions, rest = pending.partition { |row| related?(group, row) && within_bounds?(group, row) }
            break if additions.empty?

            group.concat(additions)
            pending = rest
          end

          groups << group
        end

        groups
      end

      def related?(group, candidate)
        candidate_files = candidate.last.to_set
        group.any? { |row| (row.last.to_set & candidate_files).any? }
      end

      def within_bounds?(group, candidate)
        return false if group.size >= MAX_FINDINGS
        (group.flat_map(&:last) + candidate.last).uniq.size <= MAX_FILES
      end

      def problem(group)
        files = group.flat_map(&:last).uniq.sort
        primary = group.map { |_path, law, _message, _related| LAW_OPERATIONS.fetch(law, "recommend") }.uniq
        candidates = primary.flat_map { |operation| OPERATION_ALTERNATIVES.fetch(operation, [operation]) }
          .select { |operation| operation == "recommend" || operation_exists?(operation) }
          .uniq
          .sort_by { |operation| operation_position(operation) }

        laws = group.map { |_path, law, _message, _related| law }.uniq
        id_source = [files, rules, group.map { |path, law, message, _| [path, law, message] }].inspect
        id = Digest::SHA256.hexdigest(id_source)[0, 10]

        confidence =
          if group.size >= 3 && laws.size >= 2 && files.size >= 2
            :high
          elsif group.size >= 2
            :medium
          else
            :single
          end

        reason = if laws.size > 1
                   "correlated #{laws.size} laws across #{files.size} files"
                 elsif files.size > 1
                   "#{group.size} findings share an affected file set"
                 else
                   "one law signal with #{files.size} affected file(s)"
                 end

        Problem.new(
          id:,
          findings: group.freeze,
          files: files.freeze,
          primary_operations: primary.freeze,
          candidate_operations: candidates.freeze,
          confidence:,
          reason:
        )
      end

      def operation_exists?(operation)
        @plan.operation(operation)
        true
      rescue ArgumentError, KeyError
        false
      end

      def operation_position(operation)
        @plan.operation(operation).position
      rescue KeyError
        999
      end
    end
  end
end
