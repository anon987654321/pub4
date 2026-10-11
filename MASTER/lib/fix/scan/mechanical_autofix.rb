# frozen_string_literal: true

require_relative "../ast_fixer"
require_relative "../write_guard"

module Master
  module Fix
    module Scan
      # Deterministic AstFixer pass behind `/review --only scan --apply`.
      # Only runs on files that have findings whose law has auto_fix=true.
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
        # status is :unchanged, :dirty, :refused or :written; content is what the
        # file holds after, reason says why a write was refused.
        Rewrite = Struct.new(:status, :content, :transforms, :reason, keyword_init: true)

        def self.enabled?(env: ENV)
          env.fetch("MASTER_SCAN_AUTOFIX", "1") != "0"
        end

        def initialize(scanner:, root:, event_bus: nil, write_guard: nil, dirty: nil)
          @scanner = scanner
          @dirty = dirty
          @root = root.to_s
          @bus = event_bus
          @write_guard = write_guard
        end

        def apply(pairs)
          autofixable_paths(pairs).filter_map { |path| fix_path(path) }
        end

        # The one propose, guard, write pipeline. A file the dirty predicate
        # names is left alone, so an autofix never entangles another session's
        # uncommitted edit; the caller reports what the status means.
        def rewrite(path, source)
          return Rewrite.new(status: :dirty, content: source, transforms: []) if dirty?(path)

          candidate = AstFixer.propose(path, source, event_bus: @bus)
          return Rewrite.new(status: :unchanged, content: source, transforms: []) unless candidate&.changed

          verdict = write_guard.verdict(path:, content: candidate.content)
          return Rewrite.new(status: :refused, content: source, transforms: [], reason: verdict.reason) if verdict.blocked?

          AstFixer.write(path, candidate.content, event_bus: @bus, transforms: candidate.transforms)
          Rewrite.new(status: :written, content: candidate.content, transforms: candidate.transforms)
        end

        private

        def fix_path(path)
          return unless File.file?(path)

          outcome = rewrite(path, File.read(path, encoding: "UTF-8"))
          rel = relative_path(path)
          case outcome.status
          when :refused
            @bus&.publish("scan_autofix:refused", path: rel, reason: outcome.reason)
            nil
          when :written
            @bus&.publish("scan_autofix:applied", path: rel, transforms: outcome.transforms)
            Applied.new(path: rel, transforms: outcome.transforms)
          end
        end

        # Shared-worktree safety: never rewrite a file that already has
        # uncommitted MODIFICATIONS. Untracked-new files are fine to fix
        # (nothing to clobber).
        def dirty?(path)
          @dirty ? @dirty.call(path) : uncommitted_modification?(path)
        end

        def uncommitted_modification?(path)
          out, status = Master::Io::Exec.capture2e("git", "-C", @root, "status", "--porcelain", "--", path.to_s, timeout: 15)
          raise "git status failed" unless status.success?
          # XY porcelain codes: skip tracked-modified (" M", "MM", "AM", "RM").
          out.to_s.lines.any? { |line| line =~ /\A(\sM|MM|AM|RM)/ }
        rescue StandardError => e
          @bus&.publish("scan_autofix:git_status_unavailable", path: relative_path(path), error: e.message)
          true
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
          law = laws_by_id[Master::Review::Scan::Finding.read(finding, :law).to_s]
          law&.auto_fix
        end

        def laws_by_id
          @laws_by_id ||= scanner_laws.to_h { |law| [law.id.to_s, law] }
        end

        def scanner_laws
          return @scanner.laws if @scanner.respond_to?(:laws)

          []
        end
      end
    end
  end
end
