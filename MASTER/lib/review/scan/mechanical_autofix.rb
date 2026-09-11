# frozen_string_literal: true

require "shellwords"
require_relative "ast_fixer"
require_relative "write_guard"

module Master
  module Review
    module Scan
      # Deterministic AstFixer pass shared by /scan and /self.
      # Only runs on files that have findings whose rule has auto_fix=true.
      # Idempotent; safe to re-run. Opt out with --dry-run, --no-autofix, or MASTER_SCAN_AUTOFIX=0.
      #
      # This is the governed writer, and that word is the change. AstFixer used
      # to transform and write in one call, so the only thing standing between a
      # misfiring transform and the file was the transform's own judgement — and
      # TODO.md records the trial run where one in three writes was damage, one
      # of them a template-literal rewrite that `node --check` waved through.
      # AstFixer proposes a candidate now; the same WriteGuard that judges every
      # constitutional write judges this one, and only what a fix *introduces*
      # can refuse it, so a file already carrying debt stays repairable.
      class MechanicalAutofix
        Applied = Struct.new(:path, :transforms, keyword_init: true)

        def self.enabled?(env: ENV)
          env.fetch("MASTER_SCAN_AUTOFIX", "1") != "0"
        end

        def initialize(scanner:, root:, event_bus: nil, write_guard: nil)
          @scanner = scanner
          @root = root.to_s
          @bus = event_bus
          @write_guard = write_guard
        end

        def apply(pairs)
          autofixable_paths(pairs).filter_map { |path| fix_path(path) }
        end

        private

        def fix_path(path)
          return unless File.file?(path)
          # Shared-worktree safety: never rewrite a file that already has
          # uncommitted MODIFICATIONS — autofixing on top of another agent's
          # in-progress edits silently entangles them and can't be cleanly split
          # at commit time. Untracked-new files are fine to fix (nothing to clobber).
          return if uncommitted_modification?(path)

          candidate = AstFixer.propose(path, File.read(path, encoding: "UTF-8"), event_bus: @bus)
          return unless candidate&.changed

          rel = relative_path(path)
          verdict = write_guard.verdict(path:, content: candidate.content)
          if verdict.blocked?
            @bus&.publish("scan_autofix:refused", path: rel, reason: verdict.reason)
            return
          end

          transforms = candidate.transforms
          AstFixer.write(path, candidate.content, event_bus: @bus, transforms:)
          applied = Applied.new(path: rel, transforms:)
          @bus&.publish("scan_autofix:applied", path: rel, transforms:)
          # Back-compat event name used by SelfScan consumers/tests
          @bus&.publish("self_autofix:applied", path: rel, transforms:)
          applied
        end

        def uncommitted_modification?(path)
          out = `git -C #{Shellwords.escape(@root)} status --porcelain -- #{Shellwords.escape(path.to_s)} 2>/dev/null`
          # XY porcelain codes: skip tracked-modified (" M", "MM", "AM", "RM").
          out.to_s.lines.any? { |line| line =~ /\A(\sM|MM|AM|RM)/ }
        rescue StandardError
          false
        end

        # Built once and lazily: WriteGuard.default constructs a scanner over the
        # whole tree, which a dry run or a disabled pass must not pay for.
        def write_guard
          @write_guard ||= WriteGuard.default
        end

        def relative_path(path)
          prefix = "#{@root}/"
          path.to_s.start_with?(prefix) ? path.to_s.delete_prefix(prefix) : path.to_s
        end

        def autofixable_paths(pairs)
          Array(pairs).filter_map do |path, file_result|
            findings = Result.wrap(file_result).value_or([])
            path if findings.any? { |finding| autofixable_finding?(finding) }
          end.uniq
        end

        def autofixable_finding?(finding)
          rule = rules_by_id[Finding.read(finding, :rule).to_s]
          rule&.auto_fix
        end

        def rules_by_id
          @rules_by_id ||= scanner_rules.to_h { |rule| [rule.id.to_s, rule] }
        end

        def scanner_rules
          return @scanner.rules if @scanner.respond_to?(:rules)

          Array(@scanner.instance_variable_get(:@rules))
        end
      end
    end
  end
end
