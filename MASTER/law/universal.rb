# frozen_string_literal: true

# law/universal.rb — every universal law, one Law.define per rule.
# Was 15 one-rule files; Law.load_all and every fixture proof are
# unchanged by the grouping (2026-08-19 file-sprawl consolidation).

# DEAD_CODE lives once, in the registry (ruby_rules.rb): it anchors the
# terminator to the line start, walks indentation to tell a dedent (block
# over, next line reachable) from a continuation, and knows else/elsif/when/
# rescue/ensure open new reachability. This file regex called `x = return_val`
# a terminator and every method's last line unreachable.

# Migrated from data/rules.yml FAIL_VISIBLY. Folds BARE_RESCUE (identical detector).
Law.define(:FAIL_VISIBLY) do
  source "Fail Fast (Jim Shore, IEEE Software 2004)"
  severity :error
  detect { |line| line.match?(/(?<![\w:.])rescue\s*$|(?<![\w:.])rescue\s+Exception\b/) }
  fix "Catch specific errors, log context, re-raise or return Result."
  bad "rescue Exception"
  good "rescue IOError => e"
end

# Migrated from data/rules.yml FULL_BY_DEFAULT.
Law.define(:FULL_BY_DEFAULT) do
  source "MASTER-native (no shallow/lite tiers by default)"
  severity :warn
  # Both words have to be list items, not two adjectives that happen to meet.
  # "sculpted soft key light, deep muted tones" is a prompt describing a
  # photograph and "blue-hour ambient light, deep shadow tones" is a colour
  # grade; the first tier word has to open a list or follow a separator, the way
  # `[shallow, deep]` does.
  detect { |line| line.match?(/(?:\A\s*|[\[(|,=:]\s*)(shallow|standard|quick|lite|basic|light|simple)\b\s*[|,)\]]\s*\b(deep|full|advanced|complete|thorough)\b/) }
  fix "Drop the degraded tier. If a real cost tradeoff exists, rename to surface the cost (lexical < structural < semantic), not the result quality."
  bad "modes = [shallow, deep]"
  good "modes = [deep]"
end

# Migrated from data/rules.yml GUARD_EXPENSIVE_OPS. Narrowed 2026-08-21 after
# the fleet-wide deep scan: of twenty production hits sampled, thirteen were
# Rails' String#truncate (the word was meant for SQL TRUNCATE) and seven were
# association- or where-scoped deletes bounded by a parent record — zero were
# the table-wide sweep this law exists to stop. It now fires on a delete with
# a bare constant receiver (Model.delete_all — the whole table), on
# drop_table, SQL TRUNCATE, and rm -rf; a scoped chain is proportionate by
# construction. Seeds, tests and migrations reset data as their job.
Law.define(:GUARD_EXPENSIVE_OPS) do
  source "MASTER-native (guard expensive operations); Nielsen heuristic 5, error prevention"
  severity :error
  path_exclude %r{/test/|/spec/|/db/seeds|/db/migrate/|seeder|demo_seed|_seed\b}
  # `rm -rf` left for NEVER_BATCH_DELETE, which already owned file deletion and
  # already knew a scoped path from an unbounded one. Both laws claiming it was
  # one question with two instruments, and every one of the twelve hits here was
  # a bounded removal in the deploy pipeline — `doas rm -rf "${app_dir}/public"`
  # — or prose in a runbook. This law is the database sweep.
  #
  # A symbol list names the operations; it does not perform them.
  # Ground::Policy::Workflow's CONFIRM is exactly that, and reading it as a
  # drop_table is reading a menu as a meal.
  detect do |line|
    next false if line.match?(/%[iw]\[/)

    line.match?(/\b[A-Z]\w*(?:::\w+)*\.(?:delete_all|destroy_all)\b|\bdrop_table\b|\bTRUNCATE\b|\btruncate_tables?\b/)
  end
  fix "Cost estimate before execution. Require opt-in for danger; scope the delete to a parent."
  bad "Session.delete_all"
  good "user.sessions.delete_all"
end

# LAW_OF_DEMETER lives once, in the registry (universal_rules.rb), which
# folds MESSAGE_CHAIN: it excludes numeric dot-chains (1.2.3.4 is an IP,
# not a message chain), stdlib transformation chains (.to_s.strip.empty? is
# idiomatic), and re-tests after blanking strings and parens. This bare
# regex flagged every version number and gem constraint in the tree.

# Migrated from data/rules.yml MEANINGFUL_NAMES.
Law.define(:MEANINGFUL_NAMES) do
  source "Clean Code — meaningful names (Robert C. Martin)"
  severity :info
  # The right-hand side has to already carry a better name, which is what the
  # fixtures below describe: `tmp = load` wastes the name `load` that is right
  # there. Any generic name on the left was 484 findings, and a sample of them
  # was `data = YAML.safe_load(path)`, `result = ideation.ideate(goal)` and
  # `result = img_f * (1.0 - intensity)` — expressions whose value genuinely is
  # the parsed data or the result, with no domain word going spare. Renaming
  # those makes the code worse, and 457 of the 484 were that shape.
  #
  # An expression with arguments, arithmetic or a literal is exempt for the same
  # reason: there is no name in it to prefer, and three more shapes where the
  # generic name is the right one and there is nothing
  # better to take: `@data = data` is the constructor idiom and has no other name
  # available; `result = blk.call` names a result after a call whose own last
  # word is `call`; and `@data = load_data` is already named after the method
  # that produced it, which is the rule satisfied rather than broken.
  detect do |line|
    next false unless line.match?(/\b(tmp|temp|data|result|val|ret|obj|str|arr|buf)\s*=\s*@?[a-z_]\w*(?:\.\w+)*\s*(?:#.*)?$/)

    left, right = line.match(/@?(\w+)\s*=\s*@?([\w.]+)/)&.captures
    next false if left.nil?
    next false if left == right                                   # @data = data
    next false if right.match?(/\.(?:call|run|value|result)\z/)   # a call's result
    next false if right.split(".").last.to_s.include?(left)       # @data = load_data
    next false if right == "nil"                                  # nothing to name it after

    true
  end
  fix "Name it after what the right-hand side already calls it, or after the domain."
  bad "tmp = load"
  good "user_profile = load"
end

# Migrated from data/rules.yml NO_COLUMN_ALIGN. The registry twin skipped
# block-comment continuations (`* …`) and ruler lines; both guards moved
# here with the retirement.
Law.define(:NO_COLUMN_ALIGN) do
  source "Ruby Style Guide / RuboCop Layout — no token alignment"
  severity :info
  # The character class before `=` is optional. Required, it could only match by
  # backtracking into the run of spaces, so `name    = 1` was caught on three
  # spaces and `result  = x` slipped through on exactly two — the commonest
  # spacing of all. 121 findings under MASTER/lib became 154, and none of the 33
  # is in law/, so the rule was blind to a third of its own subject.
  # A run of spaces inside a quoted string is the string. OPENBSD/dev/perms.sh
  # writes `print "File perms  = $file_perms"`, lining up two labels in the
  # OUTPUT — the one place column alignment is the point rather than the defect.
  detect do |line|
    s = line.strip
    next false if s.start_with?("*") || s.match?(/\A[-=]+\z/)

    line.gsub(/"[^"\n]*"|'[^'\n]*'/) { |m| "\0" * m.length }
        .match?(/\S {2,}(?:=>|[^=!<>=]?=[^=>]|:\s)/)
  end
  fix "Remove padding; one space before operators. Column alignment decays and hides diffs."
  bad "name    = 1"
  good "name = 1"
end

# NO_FLAG_ARGUMENTS lives once, in the registry (universal_rules.rb): only
# a positional boolean default is a flag argument; a keyword default
# (stream: false) is fine API design, and this bare regex flagged every one.

# Migrated from data/rules.yml NULL_BLINDNESS. The second retired twin: the
# registry version's regex flagged IS NULL — the correct form its own message
# prescribes — and survived on a path exemption; this detector flags the
# defect, and the good fixture below is the line the registry version would
# have failed on. A comment only talks about the pattern.
Law.define(:NULL_BLINDNESS) do
  source "SQL/Ruby — explicit NULL/nil handling"
  severity :error
  # `= NULL` with no word boundary matched `<= NULL_FLOOR_DB` and
  # `>= NULL_FLOOR_DB` — a float comparison against a dB floor, flagged at
  # error severity, which then gated those files out of the semantic pass
  # entirely. `!= NULL` was also a strict substring of `= NULL`, so that half
  # of the alternation had never done anything.
  detect do |line|
    (s = line.strip) && !s.start_with?("#") &&
      s.match?(/(?:(?<![<>=!])=|!=)\s*NULL\b|== nil.*column|column.*== nil/)
  end
  fix "Use IS NULL / IS NOT NULL in SQL; .nil? in Ruby."
  bad "WHERE deleted_at = NULL"
  good <<~X
    WHERE deleted_at IS NULL
    # `= NULL` -> `IS NULL`, in SQL and nowhere else.
  X
end

# Migrated from data/rules.yml SECRET_PROXIMITY.
Law.define(:SECRET_PROXIMITY) do
  source "OWASP — no hardcoded secrets/credentials"
  severity :error
  # A literal "password" in a test or seed IS the fixture — both fleet hits
  # were user.password = "password" in exactly those files (2026-08-22).
  path_exclude %r{/test/|/spec/|/db/seeds}
  # The value must be a CLOSED quoted literal, and the identifier must not
  # itself sit inside a string. `[^'"]{8,}` had no reason to stay inside a
  # quote, so it matched the source BETWEEN two literals — the "secret" it
  # reported in auth_tier.rb was the code `token=") || p == `. At :error
  # severity, which also gated that file out of the semantic pass.
  #
  # An interpolated value is assembled at run time and cannot BE a literal
  # secret. `token = "#{vertical}_#{key}"` builds a design-token name, and the
  # literal is the whole point of the rule.
  detect do |line|
    # Shell expansion counts too: `export HUGGINGFACE_HUB_TOKEN="${HF_TOKEN}"`
    # forwards a value the environment already holds, which is the fix this rule
    # asks for rather than the defect it names.
    next false if line.match?(/=\s*"[^"\n]*(?:#\{|\$\{|\$\w)/)

    line.match?(/(?<!['"])(password|secret|token|api_key|private_key)\s*=\s*(?:"[^"\n]{8,}"|'[^'\n]{8,}')/i)
  end
  fix "Move secret to environment variable or secrets manager."
  bad "api_key = 'sk_live_abcdef123456'"
  good "api_key = ENV.fetch('API_KEY')"
end

# Migrated from data/rules.yml SQUINT_TEST. Folds WHITESPACE_PUNCTUATION (identical detector).
Law.define(:SQUINT_TEST) do
  source "Squint Test readability heuristic (Sandi Metz)"
  severity :info
  scope :file
  # Comment lines are content for this law, not noise. considered_text replaces
  # each one with a bare newline, so any four consecutive comment lines became
  # `\n\n\n\n` and read as a gap — which made every heavily-commented file in
  # this tree, including every file under law/, a finding about blank lines it
  # does not have.
  reads_comments true
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
#
# String literals blank before matching (2026-08-21): the queue's final four
# findings were all the WORD inside quotes — a scanner's own finding message,
# an SSE body saying "retry in 30s", the SOA retry field name. The keyword
# can never be inside a string; prose about retrying is not a retry.
Law.define(:UNBOUNDED_RETRY) do
  source "Release It! — retry budgets / bounded retries (Nygard)"
  severity :error
  # Every finding this produced was a false positive, all five of them. Three
  # narrowings, each against one of those shapes:
  #
  # A retry whose modifier bounds it IS the fix — `retry if attempts < RETRIES`
  # is what "add a max_attempts cap" looks like once someone has added it, and
  # flagging it asks for the change that is already there.
  #
  # `while true` left the rule. A supervisor loop that sleeps is not a retry: it
  # is how every watcher in this tree is written, the bad fixture below is a
  # bare `retry` rather than a loop, and the one hit was OPENBSD's file watcher
  # doing its job. A rule about busy loops needs to see the body for a sleep,
  # which is file scope and a different rule.
  #
  # The keyword has to be a statement. String blanking cannot survive a nested
  # interpolation — `"CSS#{a ? " (retry)" : ""}"` left the word bare — and a
  # `retry` that is not at the head of a statement is prose in every case.
  #
  # One line on purpose: Law.conduct neutralizes `detect` lines when a law
  # judges law/, and it reads lines, not blocks.
  detect { |line| (s = line.strip) && !s.start_with?("#") && !s.match?(/retry\\/) && !s.match?(/\bretry\s+(?:if|unless)\b[^\n]*[<>]/) && (b = s.gsub(/"(?:\\.|[^"\\])*"/, '""').gsub(/'[^']*'/, "''")) && b.match?(/\A(?:.*(?:;|\bthen\b|\bdo\b)\s*)?retry(?![?:\w|])/) || false }
  fix "Add max_attempts cap and exponential backoff."
  bad "retry"
  good <<~X
    next if action == :retry
    def retry?(error, attempt:)
    @bus&.publish("llm:failover_backoff", retry: retry_index + 1)
    [+0.18, :name, /retry|loop|escalat/],
    # a retry then spawned a duplicate on the same output file
    attempts += 1 and redo if attempts < 3
    message: "retry with no visible attempt counter",
    lines << "refresh %s retry" % policy.dig("soa", "retry")
  X
end

# Migrated from data/rules.yml WHY_NOT_WHAT.
# Distinct from WHY_NOT_WHAT, which is about a comment restating the code beside
# it. This one is about a comment that records the edit history of the line.
# Git already holds that, per line, with an author and a message, and never
# drifts from it; a comment holding the same thing is a second copy that decays
# the first time someone edits the code and not the paragraph above it. The homes
# for a reason worth re-reading are DECISIONS.md and DEBT.md.
#
# Narrow on purpose. "Measured 2026-08-11: /home is at 89%" is evidence for a
# present claim and stays. What this catches is a dated change verb and the
# past-tense framing of a line's earlier content, which carry no reason at all.
# Counted across the tree before landing: 47 lines, none of them in law/.
Law.define(:NO_CHANGELOG_COMMENT) do
  source "MASTER-native — git holds history; comments hold reasons"
  severity :warn
  reads_comments true
  detect do |line|
    line.match?(/^\s*(?:#|\/\/|\*)\s*(?:RAISED|TRIMMED|UPDATED?|RENAMED|MOVED|CHANGED|REVERTED|REMOVED|ADDED|DEPRECATED|NARROWED|REDUCED|FIXED)\b[^\n]{0,40}\d{4}-\d{2}-\d{2}/i) ||
      line.match?(/^\s*(?:#|\/\/|\*)[^\n]{0,60}\b(?:used to be|was previously|were previously|formerly)\b/i) ||
      line.match?(/^\s*(?:#|\/\/|\*)[^\n]{0,60}\bchanged from\b[^\n]{0,40}\bto\b/i)
  end
  fix "State the present reason. Put the history in the commit message, or in DECISIONS.md if it must be read again."
  bad "# RENAMED 2026-08-25 from Foo to Bar"
  good "# Bar names what it returns, so a caller can tell it from Baz."
end

Law.define(:WHY_NOT_WHAT) do
  source "Clean Code / Code Complete — comments explain why, not what"
  severity :info
  reads_comments true
  # Two guards, and the second is the one that matters. Anchoring to the start
  # of the comment is not enough, because these words are nouns as often as
  # verbs and a wrapped paragraph puts them at the head of a line: "# set is
  # closed and small" is about the verb SET, "# create is not a failure to
  # lock" is about the create call. All six hits read that way.
  #
  # A comment restating the line below it is terse — that is what makes it
  # worthless, and the fixture is two words. Prose that explains why runs on.
  # Four words is the cut, so `# increment counter` stays caught and a sentence
  # that merely opens with one of these words does not.
  detect do |line|
    body = line[/\A\s*#\s*(.*)/, 1].to_s
    # A restating comment names its object: "increment counter". A function word
    # after the verb means the line is mid-sentence — "get for free" is the tail
    # of "what changed is which one you / get for free", wrapped.
    next false unless body.match?(/\A(increment|set|get|update|return|initialize|create|add)\s+\w+/)
    next false if body.match?(/\A\w+\s+(?:a|an|the|for|of|to|in|on|at|with|from|by|is|are|was|were|it|this|that)\b/)

    body.split.length <= 4
  end
  fix "Comments should explain intent, not restate the code."
  bad "# increment counter"
  good "# retries are capped so a flapping host cannot pin the worker"
end
