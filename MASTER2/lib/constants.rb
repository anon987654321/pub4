# frozen_string_literal: true

module MASTER
  # Constants - single source of truth for axiom names and shared magic numbers.
  # Hoist here rather than defining inline in method bodies (STRUCTURAL_INTEGRITY axiom).
  module Constants
    # Axiom identifiers (ONE_SOURCE: referenced by name, not repeated strings)
    FAIL_VISIBLY = "FAIL_VISIBLY"
    ONE_SOURCE   = "ONE_SOURCE"
    KISS         = "KISS"
    SELF_APPLY   = "SELF_APPLY"

    # Shared size limits used across executor tools and output formatting
    MAX_FILE_CONTENT         = 3_000   # chars of file content passed to LLM
    MAX_SHELL_OUTPUT         = 1_000   # chars of shell output passed to LLM
    MAX_LLM_RESPONSE_PREVIEW = 1_000   # chars shown in debug previews
  end
end
