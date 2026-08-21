# frozen_string_literal: true

# law/universal.rb — every universal law, one Law.define per rule.
# Was 15 one-rule files; Law.load_all and every fixture proof are
# unchanged by the grouping (2026-08-19 file-sprawl consolidation).

# Migrated from data/rules.yml DEAD_CODE.
Law.define(:DEAD_CODE) do
  source "Refactoring — remove dead code (Fowler) / Clean Code"
  severity :warn
  scope :file
  detect { |text| text.match?(/(?:return|exit|raise|throw)\b(?![^\n]*\b(?:if|unless)\b)[^\n]*\n\s*\w+/m) }
  fix "Remove code after return/exit/raise/throw."
  bad <<~X
    return x
    cleanup
  X
  good <<~X
    return x if done
    cleanup
  X
end

# Migrated from data/rules.yml FAIL_VISIBLY. Folds BARE_RESCUE (identical detector).
Law.define(:FAIL_VISIBLY) do
  source "Fail Fast (Jim Shore, IEEE Software 2004)"
  severity :error
  detect { |line| line.match?(/(?<![\w:.])rescue\s*$|(?<![\w:.])rescue\s+Exception\b/) }
  fix "Catch specific errors, log context, re-raise or return Result."
  bad  "rescue Exception"
  good "rescue IOError => e"
end

# Migrated from data/rules.yml FULL_BY_DEFAULT.
Law.define(:FULL_BY_DEFAULT) do
  source "MASTER-native (no shallow/lite tiers by default)"
  severity :warn
  detect { |line| line.match?(/\b(shallow|standard|quick|lite|basic|light|simple)\b\s*[|,)\]]\s*\b(deep|full|advanced|complete|thorough)\b/) }
  fix "Drop the degraded tier. If a real cost tradeoff exists, rename to surface the cost (lexical < structural < semantic), not the result quality."
  bad  "modes = [shallow, deep]"
  good "modes = [deep]"
end

# Migrated from data/rules.yml GUARD_EXPENSIVE_OPS.
Law.define(:GUARD_EXPENSIVE_OPS) do
  source "MASTER-native (guard expensive operations); Nielsen heuristic 5, error prevention"
  severity :error
  detect { |line| line.match?(/\b(delete_all|destroy_all|drop_table|truncate)\b|rm\s+-rf\b/) }
  fix "Cost estimate before execution. Require opt-in for danger."
  bad  "Session.delete_all"
  good "Session.where(expired: true).find_each(&:destroy)"
end

# Migrated from data/rules.yml LAW_OF_DEMETER. Folds MESSAGE_CHAIN (identical detector).
Law.define(:LAW_OF_DEMETER) do
  source "Law of Demeter (Ian Holland, Northeastern, 1987)"
  severity :warn
  detect { |line| line.match?(/\w+\.\w+\.\w+\.\w+/) }
  fix "Add delegate method. Talk only to direct collaborators."
  bad  "order.customer.address.city"
  good "order.shipping_city"
end

# Migrated from data/rules.yml MEANINGFUL_NAMES.
Law.define(:MEANINGFUL_NAMES) do
  source "Clean Code — meaningful names (Robert C. Martin)"
  severity :info
  detect { |line| line.match?(/\b(tmp|temp|data|result|val|ret|obj|str|arr|buf)\b\s*=/) }
  fix "Use domain-specific names. user_profile, error_message."
  bad  "tmp = load"
  good "user_profile = load"
end

# Migrated from data/rules.yml NO_COLUMN_ALIGN.
Law.define(:NO_COLUMN_ALIGN) do
  source "Ruby Style Guide / RuboCop Layout — no token alignment"
  severity :info
  detect { |line| line.match?(/\S {2,}(?:=>|[^=!<>]=[^=>]|:\s)/) }
  fix "Remove padding; one space before operators. Column alignment decays and hides diffs."
  bad  "name    = 1"
  good "name = 1"
end

# Migrated from data/rules.yml NO_FLAG_ARGUMENTS.
Law.define(:NO_FLAG_ARGUMENTS) do
  source "Clean Code — no flag arguments (Robert C. Martin)"
  severity :warn
  detect { |line| line.match?(/def \w+\([^)]*\btrue\b|def \w+\([^)]*\bfalse\b/) }
  fix "Split into two distinct units. Each does one thing."
  bad  "def render(doc, true)"
  good "def render(doc)"
end

# Migrated from data/rules.yml NULL_BLINDNESS. The second retired twin: the
# registry version's regex flagged IS NULL — the correct form its own message
# prescribes — and survived on a path exemption; this detector flags the
# defect, and the good fixture below is the line the registry version would
# have failed on. A comment only talks about the pattern.
Law.define(:NULL_BLINDNESS) do
  source "SQL/Ruby — explicit NULL/nil handling"
  severity :error
  detect { |line| (s = line.strip) && !s.start_with?("#") && s.match?(/= NULL|!= NULL|== nil.*column|column.*== nil/) }
  fix "Use IS NULL / IS NOT NULL in SQL; .nil? in Ruby."
  bad  "WHERE deleted_at = NULL"
  good <<~X
    WHERE deleted_at IS NULL
    # `= NULL` -> `IS NULL`, in SQL and nowhere else.
  X
end

# Migrated from data/rules.yml SECRET_PROXIMITY.
Law.define(:SECRET_PROXIMITY) do
  source "OWASP — no hardcoded secrets/credentials"
  severity :error
  detect { |line| line.match?(/(password|secret|token|api_key|private_key)\s*=\s*['"][^'"]{8,}/) }
  fix "Move secret to environment variable or secrets manager."
  bad  "api_key = 'sk_live_abcdef123456'"
  good "api_key = ENV.fetch('API_KEY')"
end

# Migrated from data/rules.yml SQUINT_TEST. Folds WHITESPACE_PUNCTUATION (identical detector).
Law.define(:SQUINT_TEST) do
  source "Squint Test readability heuristic (Sandi Metz)"
  severity :info
  scope :file
  detect { |text| text.match?(/\n{4,}/m) }
  fix "One blank line between sections, never more than two consecutive."
  bad <<~X
    a



    b
  X
  good <<~X
    a

    b
  X
end

# TYPOGRAPHIC_EXCELLENCE lives once, in the registry (universal_rules.rb):
# it knows shell arg separators and Open3 calls are not prose; this bare
# twin flagged doc-comment placeholders and double-counted every hit.

# TYPOGRAPHY_DISCIPLINE lives once, in the registry (universal_rules.rb): it
# skips comment-leading lines and yaml frontmatter and wants a 4+ run, where
# this per-line twin flagged every section comment, diff header and
# frontmatter delimiter in the tree.

# Migrated from data/rules.yml UNBOUNDED_RETRY. The migration regressed the
# detector to the bare word — 24 findings on lib/, every one a comment, a
# :retry symbol, a retry? method, a retry: kwarg or a regex literal, while
# the registry twin in universal_rules.rb already carries the narrowed
# keyword. The keyword never follows `:` or a word character, never
# precedes `?`, `:` or a word character, never sits beside `|`; a comment
# only talks about it.
Law.define(:UNBOUNDED_RETRY) do
  source "Release It! — retry budgets / bounded retries (Nygard)"
  severity :error
  detect { |line| (s = line.strip) && !s.start_with?("#") && !s.match?(/retry\\/) && (s.match?(/(?<![:\w|])retry(?![?:\w|])/) || s.match?(/while\s+true/)) }
  fix "Add max_attempts cap and exponential backoff."
  bad  "retry"
  good <<~X
    next if action == :retry
    def retry?(error, attempt:)
    @bus&.publish("llm:failover_backoff", retry: retry_index + 1)
    [+0.18, :name, /retry|loop|escalat/],
    # a retry then spawned a duplicate on the same output file
    attempts += 1 and redo if attempts < 3
  X
end

# Migrated from data/rules.yml WHY_NOT_WHAT.
Law.define(:WHY_NOT_WHAT) do
  source "Clean Code / Code Complete — comments explain why, not what"
  severity :info
  reads_comments true
  detect { |line| line.match?(/#\s*(increment|set|get|update|return|initialize|create|add)\s+\w+/) }
  fix "Comments should explain intent, not restate the code."
  bad  "# increment counter"
  good "# retries are capped so a flapping host cannot pin the worker"
end
