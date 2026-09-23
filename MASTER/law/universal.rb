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
  ask "Does this code swallow exceptions or fail silently instead of surfacing the error with useful context?"
  # Ruby only: `rescue` at a line end in Markdown is the English word, as in
  # "search-and-rescue" closing a sentence in AEGIS.md.
  languages %i[ruby]
  detect { |line| line.match?(/(?<![\w:.])rescue\s*$|(?<![\w:.])rescue\s+Exception\b/) }
  fix "Catch specific errors, log context, re-raise or return Result."
  bad "rescue Exception"
  good "rescue IOError => e"
end

# Migrated from data/rules.yml FULL_BY_DEFAULT.
Law.define(:FULL_BY_DEFAULT) do
  source "MASTER-native (no shallow/lite tiers by default)"
  severity :warn
  ask "Does this API expose a do-less tier such as shallow, standard, quick, lite, basic, or light alongside a full tier where users routinely need the full behavior? If the cost tradeoff is real, name the cost rather than the quality."
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
  ask "Does this execute an expensive or destructive operation without confirmation, bounds, or relevant preconditions?"
  path_exclude %r{/test/|/spec/|/db/seeds|/db/migrate/|seeder|demo_seed|_seed\b}
  # `rm -rf` left for NEVER_BATCH_DELETE, which already owned file deletion and
  # already knew a scoped path from an unbounded one. Both laws claiming it was
  # one question with two instruments, and every one of the twelve hits here was
  # a bounded removal in the deploy pipeline — `doas rm -rf "${app_dir}/public"`
  # — or prose in a runbook. This law is the database sweep.
  #
  # A symbol list names the operations; it does not perform them.
  # `%i[drop_table force_push]` is a list of what needs confirming, and reading
  # it as a drop_table is reading a menu as a meal.
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
  # A SET clause assigns, and `SET col = NULL` is how SQL clears a column; the
  # comparison this rule is about starts at WHERE, so the clause between is
  # read out before matching.
  detect do |line|
    (s = line.strip) && !s.start_with?("#") &&
      s.sub(/\bSET\b.*?(?=\bWHERE\b|\z)/i, "").match?(/(?:(?<![<>=!])=|!=)\s*NULL\b|== nil.*column|column.*== nil/)
  end
  fix "Use IS NULL / IS NOT NULL in SQL; .nil? in Ruby."
  bad "UPDATE profiles SET bydel = NULL WHERE deleted_at = NULL"
  good <<~'X'
    WHERE deleted_at IS NULL
    # `= NULL` -> `IS NULL`, in SQL and nowhere else.
    UPDATE profiles SET neighborhood_id = NULL WHERE neighborhood_id IS NOT NULL
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
  ask "Does this file have dense blocks with no visual breaks, or ragged indentation?"
  scope :file
  # Comment lines are content for this law, not noise. considered_text replaces
  # each one with a bare newline, so any four consecutive comment lines became
  # `\n\n\n\n` and read as a gap — which made every heavily-commented file in
  # this tree, including every file under law/, a finding about blank lines it
  # does not have.
  reads_comments true
  detect { |text| text.match?(/\n{4,}/m) }
  fix "One blank line between sections, never more than two consecutive."
  bad <<~'X'
    a



    b
  X
  good <<~'X'
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
  # `retry` is a Ruby keyword and nothing else. Undeclared, this read every
  # language in the tree, and its one standing finding was the word in a
  # sentence on 406-unsupported-browser.html — "then retry", English prose in
  # HTML, at :error. Every narrowing above is about telling the keyword from
  # the word; declaring the language is the same job done at the file.
  languages %i[ruby]
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
  good <<~'X'
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
# the first time someone edits the code and not the paragraph above it. A reason
# worth re-reading is a present-tense comment; unfinished work goes in TODO.md.
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
    line.match?(/^\s*(?:#|\/\/|\*)\s*(?:RAISED|RATCHETED|LOWERED|BUMPED|TRIMMED|UPDATED?|RENAMED|MOVED|CHANGED|REVERTED|REMOVED|ADDED|DEPRECATED|NARROWED|REDUCED|FIXED)\b[^\n]{0,40}\d{4}-\d{2}-\d{2}/i) ||
      line.match?(/^\s*(?:#|\/\/|\*)[^\n]{0,60}\b(?:used to be|was previously|were previously|formerly)\b/i) ||
      line.match?(/^\s*(?:#|\/\/|\*)[^\n]{0,60}\bchanged from\b[^\n]{0,40}\bto\b/i)
  end
  fix "State the present reason. Put the history in the commit message."
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


# Constitutional migration batch 2: architecture, design, and verification laws.
# Semantic laws live here once their executable question, remedy, and worked
# examples are defined. The YAML catalogue remains temporarily for compatibility;
# SemanticRule#from_law gives these definitions precedence during the migration.

Law.define(:FUNCTIONAL_CORE) do
  source "Functional Core, Imperative Shell (Gary Bernhardt)"
  severity :info
  ask "Are IO, database, network, filesystem, or process side effects scattered deep inside business logic instead of isolated at the edges?"
  fix "Return values from the core and move IO to the shell."
  bad <<~'X'
    def calculate_total(items); DB.save(calculate_total(items)); end
  X
  good <<~'X'
    total = calculate_total(items); DB.save(total)
  X
end

Law.define(:CONVENTION_OVER_CONFIG) do
  source "Convention over Configuration (Rails Doctrine, DHH)"
  severity :info
  ask "Does this require explicit configuration where an established local convention already provides the correct behavior?"
  fix "Use the existing convention; add configuration only when it changes a real requirement."
  bad <<~'X'
    config = { adapter: :default }
  X
  good <<~'X'
    adapter = default_adapter
  X
end

Law.define(:PROGRAMMER_HAPPINESS) do
  source "Optimize for Programmer Happiness (Rails Doctrine, DHH)"
  severity :info
  ask "Does this design impose ceremony or friction that does not buy meaningful safety or clarity?"
  fix "Remove unnecessary ceremony and keep the common path expressive."
  bad <<~'X'
    builder = RequestBuilder.new; builder.configure { |x| x.timeout = 30 }; builder.build
  X
  good <<~'X'
    request = Request.new(timeout: 30)
  X
end

Law.define(:OMAKASE) do
  source "The Menu Is Omakase (Rails Doctrine, DHH)"
  severity :info
  ask "Does this introduce a competing tool when the application already has a suitable integrated default?"
  fix "Use the existing integrated default unless a concrete requirement justifies deviation."
  bad <<~'X'
    require "external_queue"
  X
  good <<~'X'
    Rails.application.config.active_job.queue_adapter = :solid_queue
  X
end

Law.define(:NO_ONE_PARADIGM) do
  source "No One Paradigm (Rails Doctrine, DHH)"
  severity :info
  ask "Does this force one programming paradigm where a pragmatic combination would make the design clearer?"
  fix "Mix paradigms where each fits the problem; do not enforce uniformity for ideology's sake."
  bad <<~'X'
    class Pipeline; def call; steps.inject { |state, step| step.call(state) }; end; end
  X
  good <<~'X'
    steps.map(&:normalize).each { |step| persist(step) }
  X
end

Law.define(:BEAUTIFUL_CODE) do
  source "Exalt Beautiful Code (Rails Doctrine, DHH)"
  severity :info
  ask "Would a reader find this merely correct rather than clear, coherent, and aesthetically deliberate?"
  fix "Rewrite for structural and aesthetic clarity, not merely passing tests."
  bad <<~'X'
    if a; b; else; c; end
  X
  good <<~'X'
    value = a ? b : c
  X
end

Law.define(:SHARP_KNIVES) do
  source "Provide Sharp Knives (Rails Doctrine, DHH)"
  severity :info
  ask "Does this restrict a capable operator's legitimate power mainly to guard against a rare misuse?"
  fix "Preserve useful capability; document dangerous edges and require deliberate use."
  bad <<~'X'
    raise "forbidden" if dangerous_operation?
  X
  good <<~'X'
    dangerous_operation! # explicit operator choice
  X
end

Law.define(:INTEGRATED_SYSTEMS) do
  source "Value Integrated Systems (Rails Doctrine, DHH)"
  severity :info
  ask "Does this fragment a cohesive concern into separate services or gems without a concrete boundary that justifies it?"
  fix "Keep the concern integrated until an actual boundary, ownership, or scaling need requires extraction."
  bad <<~'X'
    HTTP.post(service_url, payload)
  X
  good <<~'X'
    Orders::Checkout.call(order)
  X
end

Law.define(:PROGRESS_OVER_STABILITY) do
  source "Progress Over Stability (Rails Doctrine, DHH)"
  severity :info
  ask "Is a beneficial breaking change being avoided solely to preserve compatibility when a clear upgrade path exists?"
  fix "Take the justified breaking change and provide an explicit migration path."
  bad <<~'X'
    def old_name(x); new_name(x); end
  X
  good <<~'X'
    def new_name(x); x; end
  X
end

Law.define(:BIG_TENT) do
  source "Push Up a Big Tent (Rails Doctrine, DHH)"
  severity :info
  ask "Does this unnecessarily exclude contributors through needless cleverness, jargon, or unexplained conventions?"
  fix "Prefer clear language and approachable structure without lowering technical rigor."
  bad <<~'X'
    raise Foo::Bar::Baz unless x && y && z
  X
  good <<~'X'
    raise InvalidState, "x requires y and z" unless x && y && z
  X
end

Law.define(:MONOLITH_FIRST) do
  source "MonolithFirst (Martin Fowler)"
  severity :info
  ask "Is this splitting a cohesive application into services before a concrete extraction boundary or operational need exists?"
  fix "Keep the feature in the application until extraction is clearly justified."
  bad <<~'X'
    PaymentsServiceClient.call(order)
  X
  good <<~'X'
    Payments::Charge.call(order)
  X
end

Law.define(:CONSISTENT_ERROR_STRATEGY) do
  source "MASTER-native (uniform error handling)"
  severity :warning
  ask "Does this module mix Result objects, exceptions, and nil returns for equivalent failure paths?"
  fix "Choose one error strategy per module and use it consistently."
  bad <<~'X'
    def find(id); raise NotFound if missing; end
  X
  good <<~'X'
    def find(id); Result.ok(record) or Result.err(:not_found); end
  X
end

Law.define(:DUAL_DETECTION) do
  source "MASTER-native (lexical + semantic detection)"
  severity :info
  ask "Does verification rely only on regex or only on an LLM when the subject can be checked with both deterministic and semantic evidence?"
  fix "Layer deterministic detection with semantic review where both add independent evidence."
  bad <<~'X'
    rule = /danger/
  X
  good <<~'X'
    rule = lexical_check + semantic_check
  X
end

Law.define(:MASS_GENERATE_CURATE) do
  source "MASTER-native (generate then curate)"
  severity :info
  ask "Is a high-stakes creative or design decision accepting the first plausible draft without exploring alternatives?"
  fix "Generate several materially different candidates, then curate against explicit constraints."
  bad <<~'X'
    solution = first_candidate
  X
  good <<~'X'
    solutions = generate(15); solution = curate(solutions)
  X
end

Law.define(:NO_SHOTGUN_SURGERY) do
  source "Refactoring code smell: Shotgun Surgery (Fowler)"
  severity :warning
  ask "Does one conceptual change require edits across many unrelated files because the missing abstraction has no single home?"
  fix "Create the missing abstraction or single source so one conceptual change has one owner."
  bad <<~'X'
    users.each { |u| audit(u) }; admins.each { |u| audit(u) }
  X
  good <<~'X'
    auditable_users.each { |u| audit(u) }
  X
end

Law.define(:NO_HIDDEN_GLOBAL_STATE) do
  source "Clean Code — avoid global mutable state (R.C. Martin)"
  severity :error
  ask "Are global variables or mutable class-level values shared across modules without explicit ownership?"
  fix "Inject configuration and state through explicit boundaries."
  bad <<~'X'
    $current_user = user
  X
  good <<~'X'
    Context.new(current_user: user)
  X
end

Law.define(:TRACER_BULLETS) do
  source "The Pragmatic Programmer — tracer bullets"
  severity :info
  ask "Is infrastructure being built without first proving the simplest end-to-end path through the real system?"
  fix "Wire the smallest end-to-end path first, prove it works, then add depth."
  bad <<~'X'
    class Queue; end; class Worker; end; class Adapter; end
  X
  good <<~'X'
    result = adapter.call(input)
  X
end

Law.define(:ORTHOGONALITY) do
  source "The Pragmatic Programmer — orthogonality"
  severity :warning
  ask "Does changing one dimension force unrelated changes in another, such as database details leaking into UI or style changing structure?"
  fix "Decouple dimensions so changes remain local."
  bad <<~'X'
    view = User.where(active: true).to_a.map { |u| "<b>#{u.name}</b>" }
  X
  good <<~'X'
    users = User.active; render_users(users)
  X
end

Law.define(:TRANSFORMATIONS) do
  source "Transformation Priority Premise (Robert C. Martin)"
  severity :info
  ask "Is the design modeling work as scattered mutable state when it can be expressed as a clear sequence of transformations?"
  fix "Express the flow as input-to-output transformations with explicit stages."
  bad <<~'X'
    state[:x] = normalize(state[:x]); state[:x] = validate(state[:x])
  X
  good <<~'X'
    validated = validate(normalize(input))
  X
end

Law.define(:DEEP_MODULES) do
  source "A Philosophy of Software Design (John Ousterhout)"
  severity :warning
  ask "Is this module shallow, exposing a complex interface while doing little work behind it?"
  fix "Absorb complexity behind a small interface that provides substantial capability."
  bad <<~'X'
    service.call(a, b, c, d, e, f, g, h)
  X
  good <<~'X'
    service.call(request)
  X
end


# Constitutional migration batch 3: kernel and foundational principles.

Law.define(:ONE_SOURCE) do
  source "DRY — The Pragmatic Programmer (Hunt & Thomas, 1999)"
  severity :error
  ask "Is the same logic or data defined in multiple authoritative places?"
  fix "Extract one authoritative representation and make all consumers reference it."
  bad <<~'X'
    MAX_RETRIES = 3; Config::MAX_RETRIES = 3
  X
  good <<~'X'
    MAX_RETRIES = Config::MAX_RETRIES
  X
end

Law.define(:DECOUPLE) do
  source "The Pragmatic Programmer — decoupling"
  severity :error
  ask "Are there implicit couplings between modules that should be explicit dependencies?"
  fix "Inject dependencies through explicit boundaries; avoid hidden global state."
  bad <<~'X'
    Mailer.send(UserStore.fetch(id))
  X
  good <<~'X'
    def initialize(mailer:, user_store:)
  X
end

Law.define(:DEGRADE_GRACEFULLY) do
  source "Release It! — graceful degradation (Michael Nygard)"
  severity :error
  ask "Does a partial dependency failure crash the whole operation when a bounded fallback is possible?"
  fix "Use timeouts, circuit breakers, bounded retries, or a safe fallback."
  bad <<~'X'
    weather = WeatherAPI.fetch!; render(weather)
  X
  good <<~'X'
    weather = WeatherAPI.fetch(timeout: 2) || cached_weather
  X
end

Law.define(:GALLS_LAW) do
  source "Gall's Law — Systemantics (John Gall, 1975)"
  severity :info
  ask "Is a complex system being built from scratch without first proving a smaller working system?"
  fix "Start with the simplest working system, prove it, then extend."
  bad <<~'X'
    class Platform; def initialize; @services = 27.times.map { Service.new }; end; end
  X
  good <<~'X'
    class Platform; def call(input); MinimalPath.call(input); end; end
  X
end

Law.define(:CHESTERTONS_FENCE) do
  source "Chesterton's Fence (G.K. Chesterton, 1929)"
  severity :warning
  ask "Is existing code being removed or changed without first understanding why it exists?"
  fix "Read history, tests, callers, and rationale before removing it."
  bad <<~'X'
    delete_legacy_authentication
  X
  good <<~'X'
    git blame lib/authentication.rb
  X
end

Law.define(:UNIX_PHILOSOPHY) do
  source "Unix philosophy — do one thing well (Doug McIlroy)"
  severity :info
  ask "Does one module perform several unrelated jobs that could compose through a clear boundary?"
  fix "Split unrelated responsibilities into focused components and compose them."
  bad <<~'X'
    class Report; def query; end; def render; end; def email; end; end
  X
  good <<~'X'
    report = Report.new(data); Email.deliver(report.render)
  X
end

Law.define(:DRY) do
  source "DRY — Don't Repeat Yourself"
  severity :warning
  ask "Are two units expressing the same knowledge independently rather than sharing one authoritative source?"
  fix "Merge the duplicated knowledge or make one representation authoritative."
  bad <<~'X'
    timeout = 30; other_timeout = 30
  X
  good <<~'X'
    timeout = DEFAULT_TIMEOUT
  X
end

Law.define(:KISS) do
  source "KISS — Keep It Simple"
  severity :warning
  ask "Does this introduce complexity the problem does not require?"
  fix "Flatten the design to the simplest structure that solves the actual problem."
  bad <<~'X'
    result = strategies.fetch(mode).call(input).then { |x| wrap(x) }.then { |x| audit(x) }
  X
  good <<~'X'
    result = process(input)
  X
end

Law.define(:LEAST_ASTONISHMENT) do
  source "Principle of Least Astonishment"
  severity :info
  ask "Do names, APIs, or behavior contradict what a reasonable reader would expect?"
  fix "Rename or reshape the interface so behavior matches its apparent meaning."
  bad <<~'X'
    users.empty? # returns true when users exist
  X
  good <<~'X'
    users.present?
  X
end

# Constitutional migration batch 4: architecture and security principles.

Law.define(:NO_GOD_CLASS) do
  source "Refactoring code smell: Large Class / God Object (Fowler)"
  severity :error
  ask "Does one class accumulate unrelated responsibilities that should have separate owners?"
  fix "Decompose into focused objects with explicit responsibilities."
  bad <<~'X'
    class Application; def users; end; def billing; end; def render; end; def mail; end; end
  X
  good <<~'X'
    class Users; end; class Billing; end
  X
end

Law.define(:FILE_SPRAWL) do
  source "MASTER-native — collapse before adding; flat hierarchy"
  severity :warning
  ask "Are tiny files or one-file directories adding structure without carrying meaningful independent responsibility?"
  fix "Absorb tiny artifacts into their natural owner before creating another boundary."
  bad <<~'X'
    lib/foo/bar.rb
  X
  good <<~'X'
    lib/foo.rb
  X
end

Law.define(:INFORMATION_HIDING) do
  source "Information hiding (David Parnas; Ousterhout)"
  severity :warning
  ask "Do implementation details leak across a module boundary so changing one decision forces unrelated callers to change?"
  fix "Encapsulate the decision behind a stable interface."
  bad <<~'X'
    renderer.backend = :cairo; renderer.options[:cairo][:antialias] = true
  X
  good <<~'X'
    renderer.render(document, quality: :high)
  X
end

Law.define(:DIFFERENT_LAYER_DIFFERENT_ABSTRACTION) do
  source "A Philosophy of Software Design — different layers, different abstractions"
  severity :warning
  ask "Do adjacent layers merely relay the same abstraction without transforming it?"
  fix "Make each layer add a meaningful abstraction or remove the layer."
  bad <<~'X'
    Controller.call(Service.call(Model.find(id)))
  X
  good <<~'X'
    controller = UsersController.new; controller.show(id)
  X
end

Law.define(:STRUCTURAL_HONESTY) do
  source "MASTER-native — structure mirrors intent"
  severity :warning
  ask "Does the artifact's structure contradict the conceptual shape of the problem?"
  fix "Align modules, sections, layout, and boundaries with the actual domain."
  bad <<~'X'
    misc/helpers/user_and_audio_and_css.rb
  X
  good <<~'X'
    users/user.rb; audio/track.rb; ui/theme.css
  X
end

Law.define(:GRACEFUL_BOUNDARIES) do
  source "Boundaries (Gary Bernhardt) — values at the edges"
  severity :info
  ask "Does a boundary assume perfect fidelity or that the other side will never change?"
  fix "Translate and validate at boundaries; define safe degradation."
  bad <<~'X'
    JSON.parse(remote_body).fetch("user")
  X
  good <<~'X'
    payload = JSON.parse(remote_body); UserPayload.parse(payload)
  X
end

Law.define(:PULL_COMPLEXITY_DOWN) do
  source "A Philosophy of Software Design — complexity belongs behind the interface"
  severity :info
  ask "Is complexity being pushed onto callers instead of absorbed by the implementation?"
  fix "Move complexity behind a small, stable interface."
  bad <<~'X'
    client.retry && client.timeout && client.auth && client.parse(response)
  X
  good <<~'X'
    client.fetch(request)
  X
end

Law.define(:ETC) do
  source "The Pragmatic Programmer — Easier To Change"
  severity :info
  ask "Does this decision unnecessarily close future options or make change expensive?"
  fix "Prefer decoupled, replaceable, reversible choices where costs are comparable."
  bad <<~'X'
    class Report < VendorSpecificReportBase; end
  X
  good <<~'X'
    class Report; def render(formatter); formatter.render(self); end; end
  X
end

Law.define(:BROKEN_WINDOWS) do
  source "The Pragmatic Programmer — broken windows"
  severity :warning
  ask "Is visible decay being left in place: dead code, stale references, broken links, or contradictory documentation?"
  fix "Fix visible decay when encountered instead of normalizing it."
  bad <<~'X'
    TODO: remove this dead branch
  X
  good <<~'X'
    return value unless value.nil?
  X
end

Law.define(:ENTROPY_RESISTANCE) do
  source "The Pragmatic Programmer — software entropy"
  severity :warning
  ask "Is disorder accumulating through inconsistent names, exceptions, stale conventions, or abandoned paths?"
  fix "Remove drift and consolidate exceptions before they become a second system."
  bad <<~'X'
    foo_name = user_name; usr = account.name
  X
  good <<~'X'
    account_name = account.name
  X
end

Law.define(:DONT_OUTRUN_HEADLIGHTS) do
  source "The Pragmatic Programmer — don't outrun your headlights"
  severity :info
  ask "Is the design specifying distant hypothetical scenarios more precisely than current evidence allows?"
  fix "Take small deliberate steps and reassess after each measured result."
  bad <<~'X'
    design_for_1000000_users = FutureArchitecture.new
  X
  good <<~'X'
    serve_current_users = SimpleApp.new
  X
end

Law.define(:REVERSIBILITY) do
  source "The Pragmatic Programmer — reversibility"
  severity :info
  ask "Is a hard-to-reverse decision being made when a reversible option provides the same present value?"
  fix "Prefer rollback paths, replaceable boundaries, and staged changes."
  bad <<~'X'
    DROP TABLE users
  X
  good <<~'X'
    rename_table :users, :users_archive
  X
end

Law.define(:DESIGN_IT_TWICE) do
  source "A Philosophy of Software Design — Design it Twice"
  severity :info
  ask "Was a consequential design committed without considering at least one materially different approach?"
  fix "Sketch and compare alternatives before committing."
  bad <<~'X'
    solution = first_design
  X
  good <<~'X'
    options = [design_a, design_b]; solution = choose(options)
  X
end

Law.define(:PROPERTY_BASED_TESTING) do
  source "Property-based testing — QuickCheck"
  severity :info
  ask "Do tests check only a few examples when the important invariant can be stated as a property?"
  fix "State the invariant and exercise many generated cases."
  bad <<~'X'
    assert_equal 3, normalize("abc").length
  X
  good <<~'X'
    assert normalize(x).length <= x.length
  X
end

Law.define(:EXPLICIT_TRADEOFF) do
  source "Polished Ruby Programming — contextual trade-offs"
  severity :info
  ask "Where several valid implementations exist, is the chosen one presented as universally correct instead of justified by context?"
  fix "State the access pattern, failure mode, or constraint that makes the choice fit."
  bad <<~'X'
    ALWAYS_USE_ASYNC = true
  X
  good <<~'X'
    # sync: bounded local workload; async would add coordination cost
  X
end

Law.define(:LEAST_PRIVILEGE) do
  source "Saltzer & Schroeder — least privilege"
  severity :error
  ask "Does a component hold broader authority than its task requires?"
  fix "Grant exactly the required scope for exactly the required duration."
  bad <<~'X'
    client = AdminClient.new; client.delete_all
  X
  good <<~'X'
    client = UserReadClient.new
  X
end

Law.define(:FAIL_SAFE_DEFAULTS) do
  source "Saltzer & Schroeder — fail-safe defaults"
  severity :error
  ask "Does the default path permit access when no explicit rule granted it?"
  fix "Default to denial and require an explicit grant."
  bad <<~'X'
    allowed = rules[user] != false
  X
  good <<~'X'
    allowed = rules.fetch(user, false)
  X
end

Law.define(:COMPLETE_MEDIATION) do
  source "Saltzer & Schroeder — complete mediation"
  severity :error
  ask "Is authority checked once and then trusted across later accesses whose state may have changed?"
  fix "Re-check authority at each access boundary."
  bad <<~'X'
    authorized = policy.allow?(user); 100.times { perform if authorized }
  X
  good <<~'X'
    100.times { perform if policy.allow?(user) }
  X
end

Law.define(:ECONOMY_OF_MECHANISM) do
  source "Saltzer & Schroeder — economy of mechanism"
  severity :warning
  ask "Is the security-critical path too large or branchy to inspect and verify as a small mechanism?"
  fix "Shrink and isolate the trusted path."
  bad <<~'X'
    def authorize; 1200 lines of mixed parsing, IO and policy; end
  X
  good <<~'X'
    def authorize(request); policy.allow?(request); end
  X
end

Law.define(:PSYCHOLOGICAL_ACCEPTABILITY) do
  source "Saltzer & Schroeder — psychological acceptability"
  severity :warning
  ask "Does the secure path impose enough friction that users are pushed toward an unsafe shortcut?"
  fix "Make the safe path the easy path and remove unnecessary security ceremony."
  bad <<~'X'
    unsafe_url = params[:url] # easier than validating
  X
  good <<~'X'
    url = Url.parse(params[:url]); fetch(url)
  X
end


# Constitutional migration batch 5: foundational architecture, clarity, and runtime behavior.

Law.define(:MAKE_ILLEGAL_STATES_UNREPRESENTABLE) do
  source "Yaron Minsky — make illegal states unrepresentable"
  severity :error
  ask "Can an invalid combination of fields or values be constructed at all, or must every caller remember a runtime check?"
  fix "Encode the invariant in the data shape, constructor, type, or boundary."
  bad <<~'X'
    User.new(role: :admin, active: false)
  X
  good <<~'X'
    ActiveAdmin.new
  X
end

Law.define(:PARSE_DONT_VALIDATE) do
  source "Alexis King — parse, don't validate"
  severity :warning
  ask "Is the same input re-checked at many call sites instead of being parsed once into a value carrying the guarantee?"
  fix "Parse once at the boundary and pass the proven value inward."
  bad <<~'X'
    def send(url); raise unless url.start_with?("https:"); fetch(url); end
  X
  good <<~'X'
    url = HttpsUrl.parse(raw); fetch(url)
  X
end

Law.define(:POKA_YOKE) do
  source "Toyota Production System — poka-yoke"
  severity :warning
  ask "Can this API be called in the wrong order, with swappable same-typed arguments, or in a meaningless state?"
  fix "Make invalid sequences or arguments difficult or impossible to express."
  bad <<~'X'
    client.send(body, token)
  X
  good <<~'X'
    client.send(token: token, body: body)
  X
end

Law.define(:COMPLEX_SYSTEMS_FAIL) do
  source "Richard Cook — How Complex Systems Fail; resilience engineering"
  severity :warning
  ask "Does this path assume the happy case or rely on a single safeguard with no defined degraded mode?"
  fix "Define independent safeguards and a bounded degraded mode."
  bad <<~'X'
    result = primary.fetch!
  X
  good <<~'X'
    result = primary.fetch(timeout: 2) || fallback.fetch
  X
end

Law.define(:STRONG_CENTERS) do
  source "Christopher Alexander — strong centers"
  severity :info
  ask "Does this artifact have one identifiable center of meaning that its parts reinforce, or is it a flat bag of unrelated pieces?"
  fix "Strengthen the central purpose and remove or relocate unrelated pieces."
  bad <<~'X'
    README with unrelated sections on finance, CSS, music, and legal notices
  X
  good <<~'X'
    README whose sections all explain how to use and govern MASTER
  X
end

Law.define(:LEVELS_OF_SCALE) do
  source "Christopher Alexander — levels of scale"
  severity :info
  ask "Does the design jump abruptly between granularities without useful intermediate levels?"
  fix "Introduce meaningful intermediate structure where it clarifies the whole."
  bad <<~'X'
    system with one 500-line method and 2-line helpers
  X
  good <<~'X'
    system with workflow -> stage -> operation
  X
end

Law.define(:GUARD_EXPENSIVE) do
  source "MASTER-native — guard expensive operations"
  severity :error
  ask "Does this file perform expensive operations without checking relevant preconditions or bounds?"
  fix "Check prerequisites, estimate cost, and bound the operation before executing it."
  bad <<~'X'
    API.delete_all
  X
  good <<~'X'
    records = API.list(limit: 100); records.each(&:delete)
  X
end

Law.define(:ARTIFICIAL_COUPLING) do
  source "The Pragmatic Programmer — avoid artificial coupling"
  severity :warning
  ask "Are unrelated concepts coupled merely because they share a container, proximity, or formatting convention?"
  fix "Separate unrelated concerns and couple only through meaningful interfaces."
  bad <<~'X'
    settings = { audio: audio, billing: billing, css: css }
  X
  good <<~'X'
    Audio::Settings.new(audio); Billing::Settings.new(billing)
  X
end

Law.define(:SELF_EXPLAINING) do
  source "Clean Code — self-documenting code"
  severity :info
  ask "Does this name clearly reveal intent without requiring a comment to decode it?"
  fix "Rename around the domain action, value, or invariant."
  bad <<~'X'
    def do_it(x)
  X
  good <<~'X'
    def refresh_access_token(token)
  X
end

Law.define(:TRAILING_COMMAS) do
  source "Ruby/JS style — trailing commas in multiline literals"
  severity :info
  ask "Does a multiline collection or argument list omit a trailing comma that stabilizes diffs?"
  fix "Add the trailing comma to multiline collections and argument lists."
  bad <<~'X'
    options = {\n  timeout: 2\n}
  X
  good <<~'X'
    options = {\n  timeout: 2,\n}
  X
end

Law.define(:SILENCE_ON_SUCCESS) do
  source "Unix philosophy — Rule of Silence"
  severity :info
  ask "Does a successful operation emit output that the operator does not need?"
  fix "Report errors and meaningful state; stay quiet on ordinary success."
  bad <<~'X'
    puts "done"
  X
  good <<~'X'
    return unless error
  X
end

Law.define(:PRECOMPUTE_MATH) do
  source "MASTER-native — precompute constant math"
  severity :info
  ask "Are invariant trig, noise, or lookup calculations repeated per frame or per object?"
  fix "Precompute invariant values once and reuse them."
  bad <<~'X'
    objects.each { |o| angle = Math.sin(Math::PI / 4) * o.scale }
  X
  good <<~'X'
    sin_quarter = Math.sin(Math::PI / 4); objects.each { |o| angle = sin_quarter * o.scale }
  X
end

Law.define(:AUDIO_SMOOTHING) do
  source "MASTER-native — audio smoothing"
  severity :info
  ask "Do visual elements jump erratically because raw audio samples drive motion directly?"
  fix "Smooth or envelope audio-derived control values before applying visual motion."
  bad <<~'X'
    scale = fft[12]
  X
  good <<~'X'
    scale = smoothing.update(fft[12])
  X
end

Law.define(:GRACEFUL_LOAD) do
  source "Web performance — progressive loading"
  severity :warning
  ask "Does this run at full quality until resource exhaustion instead of degrading in measured stages?"
  fix "Start with a safe baseline and progressively add quality within resource bounds."
  bad <<~'X'
    renderer.render(quality: :ultra)
  X
  good <<~'X'
    quality = budget.available? ? :full : :low; renderer.render(quality:)
  X
end

Law.define(:ANALOG_WARMTH) do
  source "MASTER-native — Dilla audio aesthetic"
  severity :info
  ask "Is generated audio unnaturally perfect because noise floor, saturation, timing drift, or humanized variation has been eliminated entirely?"
  fix "Introduce restrained, purposeful imperfection where the aesthetic calls for it."
  bad <<~'X'
    notes.each { |n| synth.play(n, velocity: 127, at: n.beat) }
  X
  good <<~'X'
    notes.each { |n| synth.play(n, velocity: humanize(n), at: drift(n.beat)) }
  X
end

Law.define(:DOMAIN_LANGUAGE) do
  source "Domain-Driven Design — Ubiquitous Language (Eric Evans)"
  severity :warning
  ask "Does this code or document use generic terms where the domain has a clearer established term?"
  fix "Use the vocabulary the domain actually uses."
  bad <<~'X'
    data = invoice.total
  X
  good <<~'X'
    invoice_total = invoice.total
  X
end

Law.define(:LOAD_BEARING_NAMES) do
  source "Clean Code — names carry intent"
  severity :warning
  ask "Are names vague, generic, or misleading enough that a reader cannot tell what they hold or do?"
  fix "Choose names that expose role, value, or domain meaning."
  bad <<~'X'
    data = process(input)
  X
  good <<~'X'
    normalized_invoice = normalize(input)
  X
end

Law.define(:ERROR_CONTEXT) do
  source "Context-rich error handling"
  severity :warning
  ask "Does an error or rejection omit the context needed to locate the cause and decide the next action?"
  fix "Include relevant operation, subject, and cause without leaking secrets."
  bad <<~'X'
    raise Error, "failed"
  X
  good <<~'X'
    raise Error, "invoice #{invoice.id}: payment authorization failed"
  X
end

Law.define(:COMMENTS_AS_DEODORANT) do
  source "Refactoring — comments as deodorant (Fowler/Beck)"
  severity :warning
  ask "Is a comment compensating for code or prose that could instead be rewritten to make the intent obvious?"
  fix "Refactor the underlying artifact first; keep comments for rationale that cannot be encoded directly."
  bad <<~'X'
    # increment i; i += 1
  X
  good <<~'X'
    i += 1
  X
end

Law.define(:POSTEL) do
  source "Postel's Law / Robustness Principle"
  severity :info
  ask "Does this boundary reject safely normalizable valid variation or emit unnecessarily strict structure that callers do not need?"
  fix "Normalize harmless variation at the boundary and keep emitted contracts deliberate."
  bad <<~'X'
    raise unless input == input.strip
  X
  good <<~'X'
    value = input.strip
  X
end

Law.define(:HYRUM) do
  source "Hyrum's Law"
  severity :warning
  ask "Is a change removing or altering behavior that callers may already depend on despite it never being formally documented?"
  fix "Search actual consumers and observed behavior before changing the contract; preserve or version what is relied upon."
  bad <<~'X'
    Logger.write("ok") # side effect removed as "unused"
  X
  good <<~'X'
    Logger.write("ok") # callers depend on audit output
  X
end

Law.define(:LEAKY_ABSTRACTION) do
  source "Law of Leaky Abstractions (Joel Spolsky)"
  severity :warning
  ask "Does an abstraction force callers to know implementation details it was supposed to hide?"
  fix "Hide protocol, storage, and implementation decisions behind a stable interface."
  bad <<~'X'
    store.sql("SELECT * FROM users")
  X
  good <<~'X'
    users = store.active_users
  X
end

Law.define(:TEMPORAL_COUPLING) do
  source "The Pragmatic Programmer — temporal coupling"
  severity :warning
  ask "Must callers invoke methods in a specific order without the API enforcing that sequence?"
  fix "Encode required state transitions or provide one operation representing the valid sequence."
  bad <<~'X'
    client.fetch; client.authenticate
  X
  good <<~'X'
    client = Client.authenticated; client.fetch
  X
end

Law.define(:HUMBLE_OBJECT) do
  source "Humble Object pattern (Gerard Meszaros)"
  severity :info
  ask "Is business or decision logic tangled with IO, rendering, or external APIs so isolated tests become difficult?"
  fix "Move decisions into a testable core and keep the boundary object thin."
  bad <<~'X'
    response = DB.query(sql); HTML.render(response)
  X
  good <<~'X'
    users = QueryUsers.call; HTML.render(users)
  X
end

Law.define(:PATTERN_EXTRACTION) do
  source "MASTER-native — extract recurring structure"
  severity :info
  ask "Is the code close to a known reusable pattern whose extraction would genuinely reduce complexity rather than add ceremony?"
  fix "Extract a pattern only when recurring structure earns the abstraction."
  bad <<~'X'
    if cache.hit?; cache.read; else; fetch; cache.write; end
  X
  good <<~'X'
    result = Cache.fetch(key) { fetch }
  X
end


# Constitutional migration batch 6a: SOLID and abstraction laws.

Law.define(:SRP) do
  source "SOLID — Single Responsibility Principle (Robert C. Martin)"
  severity :warning
  ask "Does this class or module have more than one reason to change?"
  fix "Give each responsibility a distinct owner and boundary."
  bad <<~'X'
    class Invoice; def calculate; end; def render; end; def email; end; end
  X
  good <<~'X'
    class Invoice; def calculate; end; end; class InvoiceRenderer; end; class InvoiceMailer; end
  X
end

Law.define(:OPEN_CLOSED) do
  source "Open-Closed Principle (Bertrand Meyer; SOLID)"
  severity :warning
  ask "Must existing core code be modified whenever a new supported variant is added?"
  fix "Extend through stable interfaces, registries, or composition where that reduces repeated core edits."
  bad <<~'X'
    case format; when :json; render_json; when :xml; render_xml; end
  X
  good <<~'X'
    renderers.fetch(format).call(document)
  X
end

Law.define(:LISKOV) do
  source "Liskov Substitution Principle (Barbara Liskov, 1987)"
  severity :warning
  ask "Does a subtype violate assumptions or guarantees established by the type it replaces?"
  fix "Make subtype behavior satisfy the established contract or use a different abstraction."
  bad <<~'X'
    class ReadOnlyStore < Store; def save(x); raise "no"; end; end
  X
  good <<~'X'
    class ReadOnlyStore < ReadStore; end
  X
end

Law.define(:INTERFACE_SEGREGATION) do
  source "SOLID — Interface Segregation"
  severity :warning
  ask "Does an interface force implementations to stub or ignore methods they do not need?"
  fix "Split broad interfaces into focused contracts."
  bad <<~'X'
    class Printer; def print; end; def scan; raise NotImplementedError; end; end
  X
  good <<~'X'
    Printable = Data.define; Scannable = Data.define
  X
end

Law.define(:DEPENDENCY_INVERSION) do
  source "SOLID — Dependency Inversion Principle"
  severity :warning
  ask "Does high-level policy directly instantiate concrete dependencies that should be replaceable?"
  fix "Depend on stable abstractions and inject concrete implementations at the boundary."
  bad <<~'X'
    class Checkout; def call; Stripe::Charge.create; end; end
  X
  good <<~'X'
    class Checkout; def initialize(payments:); @payments = payments; end; end
  X
end

Law.define(:ONE_JOB) do
  source "SRP / Unix philosophy — do one thing"
  severity :warning
  ask "Does this module handle unrelated responsibilities instead of one coherent job?"
  fix "Give the module one job and compose it with neighboring modules."
  bad <<~'X'
    class UserService; def find; end; def email; end; def export; end; end
  X
  good <<~'X'
    class UserFinder; end; class UserMailer; end; class UserExporter; end
  X
end

Law.define(:COMPOSABLE) do
  source "Unix philosophy / functional composition"
  severity :info
  ask "Is this operation monolithic when it could be cleanly composed from smaller independent parts?"
  fix "Expose small units with explicit inputs and outputs so they can be composed."
  bad <<~'X'
    processor.run_all(input)
  X
  good <<~'X'
    normalized = normalize(input); validated = validate(normalized)
  X
end

Law.define(:LAW_OF_DEMETER) do
  source "Law of Demeter (Ian Holland)"
  severity :warning
  ask "Does this code reach through several objects or expose knowledge of a collaborator's internals?"
  fix "Talk only to immediate collaborators and encapsulate the traversal."
  bad <<~'X'
    order.customer.address.city
  X
  good <<~'X'
    order.shipping_city
  X
end

Law.define(:COMPOSITION_OVER_INHERITANCE) do
  source "Design Patterns (Gang of Four)"
  severity :info
  ask "Is inheritance being used mainly for code reuse rather than a genuine substitutability relationship?"
  fix "Prefer composition when behavior can vary independently of type identity."
  bad <<~'X'
    class JsonReport < Report; end
  X
  good <<~'X'
    class Report; def initialize(formatter:); @formatter = formatter; end; end
  X
end

Law.define(:ONE_ABSTRACTION_LEVEL) do
  source "Clean Code — one level of abstraction per function"
  severity :info
  ask "Does this function mix policy-level operations with low-level representation or IO details?"
  fix "Keep each function at one conceptual level and delegate detail downward."
  bad <<~'X'
    def checkout; authorize_card; db.execute("INSERT INTO..."); render_html; end
  X
  good <<~'X'
    def checkout; authorize_card; persist_order; render_receipt; end
  X
end


# Constitutional migration batch 6b: design, functional, and refactoring laws.

Law.define(:STEPDOWN) do
  source "Clean Code — Stepdown Rule"
  severity :info
  ask "Does the code fail to read top-down from high-level intent into progressively smaller details?"
  fix "Arrange definitions so each step introduces the detail used by the next."
  bad <<~'X'
    def helper; end; def main; helper; end
  X
  good <<~'X'
    def main; helper; end; def helper; end
  X
end

Law.define(:BOUNDARY_ISOLATION) do
  source "Boundaries (Gary Bernhardt) / Clean Architecture"
  severity :warning
  ask "Does third-party API or framework surface leak directly into core logic?"
  fix "Translate external contracts at a boundary and keep the core independent."
  bad <<~'X'
    status = Stripe::Charge.create(amount: cents).status
  X
  good <<~'X'
    status = Payments::Authorization.new(gateway: stripe).call(amount)
  X
end

Law.define(:NO_MAGIC) do
  source "Clean Code — no magic numbers"
  severity :warning
  ask "Are unexplained numeric literals or booleans carrying domain meaning instead of named concepts?"
  fix "Name the domain meaning and keep the value in one source."
  bad <<~'X'
    sleep 37; if retries > 4; end
  X
  good <<~'X'
    BACKOFF_SECONDS = 37; MAX_RETRIES = 4
  X
end

Law.define(:FAIL_FAST) do
  source "Fail Fast (Jim Shore)"
  severity :warning
  ask "Does the system defer reporting a known invalid state instead of stopping at the point it is detected?"
  fix "Reject invalid state immediately with actionable context."
  bad <<~'X'
    result = parse(input); use(result) if result.valid?
  X
  good <<~'X'
    raise InvalidInput, result.error unless parse(input).ok?
  X
end

Law.define(:IDEMPOTENT) do
  source "REST / distributed systems idempotency"
  severity :info
  ask "Would repeating the same operation with the same intended input produce an unintended different result?"
  fix "Make repeat calls converge to the same state or use an idempotency key."
  bad <<~'X'
    POST /payments creates another charge every retry
  X
  good <<~'X'
    PUT /payments/123 with idempotency key
  X
end

Law.define(:DEFENSIVE_INPUT) do
  source "Defensive programming / safe boundaries"
  severity :warning
  ask "Is external or untrusted input used without checking its shape, range, encoding, or allowed values?"
  fix "Validate or parse input at the boundary before it reaches trusted logic."
  bad <<~'X'
    File.read(params[:path])
  X
  good <<~'X'
    path = SafePath.parse(params.fetch(:path)); File.read(path)
  X
end

Law.define(:GRACEFUL_DEGRADATION) do
  source "Release It! graceful degradation"
  severity :warning
  ask "Does one component failure bring down the whole operation when a bounded degraded mode is available?"
  fix "Isolate failures and provide a safe fallback or partial result."
  bad <<~'X'
    profile = ProfileAPI.fetch!; render(profile)
  X
  good <<~'X'
    profile = ProfileAPI.fetch(timeout: 2) || Profile.empty
  X
end

Law.define(:NO_SIDE_EFFECTS) do
  source "Functional programming / Clean Code"
  severity :info
  ask "Does this function silently modify external state in addition to returning its conceptual result?"
  fix "Separate side effects from pure transformation where practical."
  bad <<~'X'
    def normalize(x); DB.write(x.strip); x.strip; end
  X
  good <<~'X'
    def normalize(x); x.strip; end
  X
end

Law.define(:PURE_FUNCTIONS) do
  source "Functional programming — referential transparency"
  severity :info
  ask "Does this function depend on hidden mutable state or ambient inputs that callers cannot see?"
  fix "Pass dependencies explicitly and keep deterministic logic pure."
  bad <<~'X'
    def total(items); items.sum + Time.now.to_i; end
  X
  good <<~'X'
    def total(items, tax_rate:); items.sum * tax_rate; end
  X
end

Law.define(:PRIMITIVE_OBSESSION) do
  source "Refactoring — Primitive Obsession (Fowler)"
  severity :info
  ask "Are primitives carrying domain rules that would be clearer and safer as a value object?"
  fix "Create a focused value object when the primitive has behavior or invariants."
  bad <<~'X'
    email = "a@b.com"; Email.send(email)
  X
  good <<~'X'
    email = EmailAddress.parse(raw); Mailer.send(email)
  X
end

Law.define(:FEATURE_ENVY) do
  source "Refactoring — Feature Envy (Fowler)"
  severity :warning
  ask "Is this method more interested in another object's data than its own?"
  fix "Move the behavior toward the data it operates on or extract a suitable collaborator."
  bad <<~'X'
    def total(order); order.items.sum { |i| i.price * i.qty }; end
  X
  good <<~'X'
    class Order; def total; items.sum { |i| i.price * i.qty }; end; end
  X
end

Law.define(:MIDDLE_MAN) do
  source "Refactoring — Middle Man (Fowler)"
  severity :info
  ask "Does this class mostly delegate methods to another object without adding meaningful policy?"
  fix "Remove the unnecessary middle layer or give it a real abstraction."
  bad <<~'X'
    def name; @user.name; end; def email; @user.email; end
  X
  good <<~'X'
    attr_reader :user
  X
end

Law.define(:LAZY_CLASS) do
  source "Refactoring — Lazy Class (Fowler)"
  severity :info
  ask "Is this class too small or trivial to justify a separate abstraction boundary?"
  fix "Inline or merge it unless the boundary provides independent value."
  bad <<~'X'
    class NameHelper; def call(x); x.name; end; end
  X
  good <<~'X'
    user.name
  X
end

Law.define(:DIVERGENT_CHANGE) do
  source "Refactoring — Divergent Change (Fowler)"
  severity :warning
  ask "Is one class repeatedly changed for several unrelated causes?"
  fix "Separate the responsibilities so each has a focused reason to change."
  bad <<~'X'
    class Report; def html; end; def csv; end; def tax; end; def mail; end; end
  X
  good <<~'X'
    class Report; end; class ReportTax; end; class ReportMailer; end
  X
end

Law.define(:SPECULATIVE_GENERALITY) do
  source "Refactoring — Speculative Generality; YAGNI"
  severity :info
  ask "Is code generalized for a future requirement that has no present evidence or consumer?"
  fix "Remove speculative hooks and add abstraction when a real use case arrives."
  bad <<~'X'
    supports_five_future_formats = true
  X
  good <<~'X'
    format = :json
  X
end

Law.define(:INAPPROPRIATE_INTIMACY) do
  source "Refactoring — Inappropriate Intimacy (Fowler)"
  severity :warning
  ask "Does one class access another class's internals instead of using its public contract?"
  fix "Expose the needed behavior through the owner's interface."
  bad <<~'X'
    user.instance_variable_get(:@roles).include?(:admin)
  X
  good <<~'X'
    user.admin?
  X
end


# Constitutional migration batch 7a: user experience laws.

Law.define(:SYSTEM_STATUS) do
  source "Nielsen Heuristic #1 — Visibility of system status"
  severity :info
  ask "Does a long-running operation provide enough timely feedback for the user to know what is happening?"
  fix "Show meaningful progress, current state, or the last completed checkpoint."
  bad <<~'X'
    export_all_records # runs for minutes with no output
  X
  good <<~'X'
    export_all_records { |n| progress.report(n) }
  X
end

Law.define(:USER_CONTROL) do
  source "Nielsen Heuristic #3 — User control and freedom"
  severity :info
  ask "Can the user cancel or undo a consequential operation when doing so is technically feasible?"
  fix "Provide an explicit cancel, undo, or rollback path."
  bad <<~'X'
    publish! # irreversible and no cancel path
  X
  good <<~'X'
    publish_with_undo_window
  X
end

Law.define(:ERROR_RECOVERY) do
  source "Nielsen Heuristic #9 — help users recover from errors"
  severity :warning
  ask "Does an error explain what happened and what the user can do next?"
  fix "State the failed operation, relevant cause, and concrete recovery action."
  bad <<~'X'
    raise Error, "invalid"
  X
  good <<~'X'
    raise Error, "invoice 42: payment declined; update card and retry"
  X
end

Law.define(:AESTHETIC_MINIMALISM) do
  source "Nielsen Heuristic #8 — aesthetic and minimalist design"
  severity :info
  ask "Does this output contain information that does not earn its place for the current task?"
  fix "Remove redundant status, decoration, and secondary detail from the primary path."
  bad <<~'X'
    render title: title, debug: true, metadata: metadata, raw: raw
  X
  good <<~'X'
    render title: title
  X
end

Law.define(:MATCH_REAL_WORLD) do
  source "Nielsen Heuristic #2 — match between system and real world"
  severity :info
  ask "Does the interface expose implementation jargon where a familiar real-world term would be clearer?"
  fix "Use the user's domain vocabulary for labels, actions, and concepts."
  bad <<~'X'
    button "invoke_job_executor"
  X
  good <<~'X'
    button "Run job"
  X
end

Law.define(:RECOGNITION_OVER_RECALL) do
  source "Nielsen Heuristic #6 — recognition rather than recall"
  severity :info
  ask "Does the user need to remember information across steps that could be shown at the point of use?"
  fix "Keep relevant context, choices, and state visible where decisions happen."
  bad <<~'X'
    form.step(4) # requires remembering which file was selected
  X
  good <<~'X'
    form.step(4, file: selected_file)
  X
end

Law.define(:FLEXIBILITY_EFFICIENCY) do
  source "Nielsen Heuristic #7 — flexibility and efficiency"
  severity :info
  ask "Does the interface serve only novices or only experts when defaults and accelerators could coexist?"
  fix "Provide a sensible default plus efficient shortcuts for experienced users."
  bad <<~'X'
    editor = Editor.new(mode: :advanced)
  X
  good <<~'X'
    editor = Editor.new; editor.bind(:advanced, "A")
  X
end

Law.define(:HELP_AND_DOCUMENTATION) do
  source "Nielsen Heuristic #10 — help and documentation"
  severity :info
  ask "When the user gets stuck, is concrete, searchable, task-focused help available near the action?"
  fix "Provide focused guidance where the question arises, with an actionable next step."
  bad <<~'X'
    button "Deploy" # no explanation or error guidance
  X
  good <<~'X'
    button "Deploy"; help "Build and release the current revision"
  X
end


# Constitutional migration batch 7b: interface, LLM, and reliability laws.

Law.define(:CONSISTENCY) do
  source "Nielsen Heuristic #4 — consistency and standards"
  severity :warning
  ask "Are the same concepts, actions, or states named or presented differently in different places?"
  fix "Choose one vocabulary and interaction pattern and reuse it."
  bad <<~'X'
    button "Remove"; link "Delete"
  X
  good <<~'X'
    button "Delete"; link "Delete"
  X
end

Law.define(:COST_TRANSPARENCY) do
  source "MASTER-native — surface LLM token cost"
  severity :warning
  ask "Are LLM calls made without exposing enough token or cost information to the operator when that information is available?"
  fix "Surface measured input, output, and cost data at the appropriate operator boundary."
  bad <<~'X'
    llm.complete(prompt)
  X
  good <<~'X'
    llm.complete(prompt) # reports usage tokens=1240 cost=$0.0021
  X
end

Law.define(:CACHE_LLM) do
  source "MASTER-native — cache repeat LLM work"
  severity :info
  ask "Is the same expensive LLM request repeated when the input and relevant context are unchanged?"
  fix "Cache deterministic or safely repeatable requests with an explicit invalidation boundary."
  bad <<~'X'
    3.times { llm.complete(prompt) }
  X
  good <<~'X'
    response = cache.fetch(prompt_key) { llm.complete(prompt) }
  X
end

Law.define(:NO_FLAG_ARGUMENTS) do
  source "Clean Code — no flag arguments"
  severity :warning
  ask "Does a boolean argument make one function perform two different jobs or select unrelated behavior?"
  fix "Split the responsibilities into named operations or objects."
  bad <<~'X'
    render(document, true)
  X
  good <<~'X'
    render_full(document)
  X
end

Law.define(:NO_OUTPUT_ARGUMENTS) do
  source "Clean Code — no output arguments"
  severity :warning
  ask "Does this function mutate an input argument to return a result indirectly?"
  fix "Return the result explicitly instead of using output parameters."
  bad <<~'X'
    def normalize!(input); input.replace(input.strip); end
  X
  good <<~'X'
    def normalize(input); input.strip; end
  X
end

Law.define(:NO_SELECTOR_ARGUMENTS) do
  source "Flag arguments / selector arguments"
  severity :warning
  ask "Is an argument used mainly as a switch between distinct behaviors rather than as data?"
  fix "Expose distinct operations or strategy objects instead of hiding a dispatch behind a flag."
  bad <<~'X'
    save(record, mode: :json)
  X
  good <<~'X'
    JsonSaver.new.save(record)
  X
end

Law.define(:DESIGN_BY_CONTRACT) do
  source "Design by Contract (Bertrand Meyer)"
  severity :info
  ask "Are important preconditions, postconditions, and invariants left implicit at an interface?"
  fix "State and enforce the contract at the boundary."
  bad <<~'X'
    def divide(a, b); a / b; end
  X
  good <<~'X'
    def divide(a, b); raise ArgumentError if b.zero?; a / b; end
  X
end

Law.define(:CRASH_EARLY) do
  source "The Pragmatic Programmer — Crash Early"
  severity :warning
  ask "Does the system limp along after detecting a state that makes continued work unsafe or misleading?"
  fix "Stop at the detection point with a clear failure rather than propagating bad state."
  bad <<~'X'
    value = parse(input); use(value) despite parse_error
  X
  good <<~'X'
    raise ParseError, parse_error if parse_error
  X
end

Law.define(:DEFINE_ERRORS_OUT) do
  source "A Philosophy of Software Design — define errors out of existence"
  severity :info
  ask "Is the interface handling errors that could instead be prevented by making invalid states unrepresentable or normalizing inputs earlier?"
  fix "Redesign the interface so the problematic state cannot arise on the normal path."
  bad <<~'X'
    if config[:timeout].nil?; config[:timeout] = 30; end
  X
  good <<~'X'
    timeout = TimeoutValue.default(config[:timeout])
  X
end


# Constitutional migration batch 7c: public surface, refactoring, and prose laws.

Law.define(:SURFACE_AREA) do
  source "API design — minimize public surface area"
  severity :warning
  ask "Is the public interface larger than necessary, exposing entry points or exceptions callers do not need?"
  fix "Reduce the public contract to the smallest useful surface and keep internals private."
  bad <<~'X'
    class Client; def fetch; end; def retry; end; def parse; end; def raw_response; end; end
  X
  good <<~'X'
    class Client; def fetch; end; end
  X
end

Law.define(:PROGRESSIVE_DISCLOSURE) do
  source "Progressive disclosure (Jakob Nielsen, NN/g)"
  severity :info
  ask "Does this present all complexity at once instead of revealing detail as the user's task requires it?"
  fix "Lead with the common path and reveal advanced controls when they become relevant."
  bad <<~'X'
    settings.show_all_advanced_controls
  X
  good <<~'X'
    settings.show_basic; settings.reveal_advanced
  X
end

Law.define(:FEEDBACK_LOOPS) do
  source "Nielsen feedback / checkpoint principle"
  severity :warning
  ask "Does this perform substantial work without reporting progress, checkpoints, or a recoverable state?"
  fix "Add meaningful progress or checkpoints proportional to operation duration and risk."
  bad <<~'X'
    backup.run # 20 minutes, no checkpoints
  X
  good <<~'X'
    backup.run { |checkpoint| emit(checkpoint) }
  X
end

Law.define(:DATA_CLASS) do
  source "Refactoring — Data Class (Fowler)"
  severity :info
  ask "Does this class mainly hold data while behavior that belongs with that data is scattered across other modules?"
  fix "Move cohesive behavior toward the data owner or replace the holder with a meaningful domain abstraction."
  bad <<~'X'
    class Money; attr_reader :cents; end; Tax.total(money)
  X
  good <<~'X'
    class Money; attr_reader :cents; def taxed(rate); cents * rate; end; end
  X
end

Law.define(:PARALLEL_INHERITANCE) do
  source "Refactoring — Parallel Inheritance Hierarchies (Fowler)"
  severity :warning
  ask "Does adding a type in one hierarchy require adding a corresponding type in another hierarchy?"
  fix "Collapse the parallel hierarchies or compose the varying dimensions."
  bad <<~'X'
    JsonReport + JsonExporter; CsvReport + CsvExporter
  X
  good <<~'X'
    Report.new(formatter: JsonExporter.new)
  X
end

Law.define(:REFUSED_BEQUEST) do
  source "Refactoring — Refused Bequest (Fowler)"
  severity :info
  ask "Does a subtype or variant inherit capabilities it cannot honor and then reject or ignore most of them?"
  fix "Choose an abstraction that matches the subtype's real contract or use composition."
  bad <<~'X'
    class ReadOnly < Writable; def write; raise NotImplementedError; end; end
  X
  good <<~'X'
    class ReadOnly < Readable; end
  X
end

Law.define(:PROSE_POSITIVE_FORM) do
  source "Strunk, Elements of Style — put statements in positive form"
  severity :info
  ask "Is a statement phrased as a negation when a direct positive verb or construction says the same thing more clearly?"
  fix "Prefer the direct positive form when it preserves meaning."
  bad <<~'X'
    He did not remember the password.
  X
  good <<~'X'
    He forgot the password.
  X
end

Law.define(:PROSE_PARALLEL_FORM) do
  source "Strunk, Elements of Style — coordinate ideas in similar form"
  severity :info
  ask "Do items in a list or series mix grammatical forms where parallel structure would make the relationship clearer?"
  fix "Use the same grammatical form for coordinated items."
  bad <<~'X'
    The system must read files, validation, and to report errors.
  X
  good <<~'X'
    The system must read files, validate input, and report errors.
  X
end

Law.define(:PROSE_RELATED_WORDS) do
  source "Strunk, Elements of Style — keep related words together"
  severity :info
  ask "Is a modifier or subject separated from its referent so the sentence misreads on the first pass?"
  fix "Keep words that belong together close enough that the intended relation is immediate."
  bad <<~'X'
    The operator, after checking the logs carefully, restarted the service.
  X
  good <<~'X'
    After checking the logs carefully, the operator restarted the service.
  X
end

Law.define(:PROSE_ONE_TOPIC_PARAGRAPH) do
  source "Strunk, Elements of Style — paragraph as the unit"
  severity :info
  ask "Does a paragraph mix unrelated topics or bury its main point below secondary detail?"
  fix "Give each paragraph one controlling topic and state its point early."
  bad <<~'X'
    The paragraph opens with deployment history, then discusses pricing, then explains the test failure.
  X
  good <<~'X'
    The paragraph opens with the test failure and explains its cause and fix.
  X
end

Law.define(:GRICE_COOPERATIVE) do
  source "Grice — cooperative principle (quantity, quality, relation, manner)"
  severity :info
  ask "Does this communication say too much or too little, assert what is unverified, drift off-topic, or obscure the point through needless complexity?"
  fix "Provide the needed information, qualify uncertain claims, stay relevant, and make the path clear."
  bad <<~'X'
    The system is definitely perfect and, by the way, here are unrelated implementation details.
  X
  good <<~'X'
    The test passed locally; CI has not run yet.
  X
end
