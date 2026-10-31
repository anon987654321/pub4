# frozen_string_literal: true

module Master
  module Fix
    class RepairLoop
      # A lane answers "UNCHANGED" to decline a fix; a proposal that collapses
      # a file to a fragment is the same refusal wearing a file's clothes. The
      # 2026-09-17 RAILS run proved the escape: a fenced "UNCHANGED" passed
      # extract_code (which only tested the bare spelling), and the post-apply
      # re-scan then approved it, because one word left in a 39-line view has
      # no violations. No instrument downstream of the write can catch what
      # this catches before it, so the check lives before the write.
      module CollapseGuard
        # The refusals a lane can answer with. "clean" is deliberately absent:
        # it is a plausible file content (a test fixture chose it by instinct),
        # and a sentinel a real file can wear is a false positive by design.
        SENTINEL = /\A(?:unchanged|no\s+changes?|safe)\z/i.freeze

        # A proposal may not shrink a file below this fraction of its old size.
        # Real fixes move a few lines; this catches wholesale replacement.
        SHRINK_FLOOR = 0.4

        # Rules whose legitimate work is deleting most of a file. A DEAD_CODE
        # fix can gut a file and be right; a trailing-comma fix cannot.
        DELETION_RULES = %w[DEAD_CODE FILE_SPRAWL].freeze

        # The marker a lane leaves where it stopped writing: "# ... rest of the
        # method unchanged", "[truncated]", "<!-- continued". The shrink floor
        # cannot see it, because a proposal that stubs one method body keeps
        # most of the file. FULL.yml's v71.8 restored a file cut from 74KB to
        # 5KB, and three of its rule sets asked for this veto.
        ELISION = Regexp.union(
          /(?:\.\.\.|…)\s*(?:the\s+)?(?:rest|remaining|unchanged|continued|existing|same|omitted)\b/i,
          /\[(?:truncated|omitted|snip(?:ped)?)\]/i,
          /\b(?:rest|remainder) of (?:the |this )?(?:file|method|code|class|function|module|body)\b.{0,24}
            \b(?:unchanged|the same|omitted|as (?:is|before)|remains|continues)\b/ix,
          /\b(?:existing|previous|other) code (?:here|unchanged|omitted)\b/i,
          /<!--\s*(?:continued|rest)\b/i,
        ).freeze

        module_function

        def sentinel?(content)
          content.to_s.strip.match?(SENTINEL)
        end

        # The proposal's elision lines the original did not already have, as
        # "line: text"; a file that documents the pattern keeps its own lines.
        def elisions(proposal, original)
          had = original.to_s.each_line.grep(ELISION).map(&:strip).tally
          proposal.to_s.each_line.with_index(1).filter_map do |line, number|
            next unless line.match?(ELISION)

            key = line.strip
            if had[key].to_i.positive?
              had[key] -= 1
              next
            end
            "#{number}: #{key[0, 80]}"
          end
        end

        # Why the proposal must be rejected before it is written, or nil. The
        # sizes are the ChangeScope's, the one reading of a change every per-fix
        # check shares.
        def collapse(scope, law:, proposal:, original: nil)
          return "the proposal is the refusal word #{proposal.to_s.strip.inspect}, not a file" if sentinel?(proposal)

          elided = elisions(proposal, original)
          return "the proposal elides instead of writing the file (#{elided.first(3).join("; ")})" if elided.any?
          return if DELETION_RULES.include?(law.to_s)

          ratio = scope.size_ratio
          return unless ratio && ratio < SHRINK_FLOOR

          "the proposal is #{(ratio * 100).round}% of the file's #{scope.old_bytes} bytes, " \
            "under the #{(SHRINK_FLOOR * 100).round}% floor"
        end
      end
    end
  end
end
