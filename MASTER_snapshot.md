# MASTER Snapshot (engine+spike focus for LLM eval)
Generated: 2026-06-15T03:14:02Z
Root: pub4/MASTER

## lib/builder.rb (boot excerpt, first 40 lines)
```ruby
# frozen_string_literal: true

require "fileutils"

module Master
  module Builder
    MUTATING_TOOLS = %w[write_file str_replace ast_edit].freeze
    RING_SIZE          = 1000
    SNAPSHOT_MAX_BYTES = 50_000
    SNAPSHOT_DIRS      = %w[bin lib data].freeze

    TOOL_MAP = {
      "ReadFile" => ->(r, i) {
        Reach::ReadFile.new(root: r, undo: i[:undo], event_bus: i[:bus])
      },
      "WriteFile" => ->(r, i) {
        Reach::WriteFile.new(root: r, undo: i[:undo], governor: i[:governor],
          event_bus: i[:bus], diff_stager: i[:diff_stager])
      },
      "StrReplace" => ->(r, i) {
        Reach::StrReplace.new(root: r, undo: i[:undo], governor: i[:governor],
          event_bus: i[:bus], diff_stager: i[:diff_stager])
      },
      "BatchReplace" => ->(r, i) {
        Reach::BatchReplace.new(root: r, governor: i[:governor], event_bus: i[:bus])
      },
      "AstEdit" => ->(r, i) {
        Reach::AstEdit.new(root: r, undo: i[:undo], governor: i[:governor], event_bus: i[:bus])
      },
      "Tree" => ->(r, i) { Reach::Tree.new(root: r, event_bus: i[:bus]) },
      "ListDir" => ->(r, i) { Reach::ListDir.new(root: r, event_bus: i[:bus]) },
      "SearchFiles" => ->(r, i) { Reach::SearchFiles.new(root: r, event_bus: i[:bus]) },
      "SearchKnowledge" => ->(r, i) { Reach::SearchKnowledge.new(root: r, event_bus: i[:bus]) },
      "SymbolLookup" => ->(r, i) {
        Reach::SymbolLookup.new(code_index: i[:code_index], event_bus: i[:bus])
      },
      "Shell" => ->(r, i) { Reach::Shell.new(root: r, governor: i[:governor], event_bus: i[:bus]) },
      "GitContext" => ->(r, i) { Reach::GitContext.new(root: r, event_bus: i[:bus]) },
      "WebFetch" => ->(r, i) { Reach::WebFetch.new(governor: i[:governor], event_bus: i[:bus]) },
      "WebSearch" => ->(r, i) { Reach::WebSearch.new(governor: i[:governor], event_bus: i[:bus]) },
```

## data/soul.yml (head)
```yaml
# soul.yml — machine-enforced constitutional schema
# Human-readable narrative lives in SOUL.md.
# ABSOLUTE sections require constitutional override to amend.
# Negotiable sections: soul propose -> soul approve -> bump version.

version: "2.5.0"
persona: malay
voice: ms-MY-OsmanNeural
language:
  primary: english
  secondary: norwegian
  dialect: bokmal

prompt_ordering:
  - master_identity
  - master_output_format
  - master_meta_instruction
  - master_constitution_absolute
  - master_priority
  - master_constitution_kernel
  - master_refusal_policy
  - master_style

absolute:
  golden_rule: PRESERVE_THEN_IMPROVE_NEVER_BREAK
  sacred_paths:
    - data/
    - SOUL.md
    - CLAUDE.md
    - CONVENTIONS.md
    - README.md
    - .claude/
    - lib/judge/scan/
    - bin/cli
  anti_simulation:
```

## Evidence (spike complete):
- Engine terse 10L: shared/engine.rb autoload + Shared.concern(n)
- 6/6 Gemfiles: pub4-shared path
- Pruned stray nested dir "amber brgen..."
- Deprecated installs + WIRING updated to engine model
- Root snapshots for other LLMs
- See MASTER/TODO.md O section + DEPLOY/TODO AN for full
- No local md bloat; relative paths; light ops
