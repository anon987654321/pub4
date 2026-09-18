# frozen_string_literal: true

# frozen_string: true

module Master
  module Fix
    class RuleLoop
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

        module_function

        def sentinel?(content)
          content.to_s.strip.match?(SENTINEL)
        end

        # true means reject the proposal before it is written.
        def collapse?(rule_id, old_src, new_src)
          return true if sentinel?(new_src)

          return false if DELETION_RULES.include?(rule_id.to_s)

          old_bytes = old_src.to_s.bytesize
          return false if old_bytes.zero?

          new_src.to_s.bytesize < (old_bytes * SHRINK_FLOOR)
        end
      end
    end
  end
end
