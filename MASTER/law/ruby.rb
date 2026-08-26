# frozen_string_literal: true

# law/ruby.rb — every ruby law, one Law.define per rule.
# Was 25 one-rule files; Law.load_all and every fixture proof are
# unchanged by the grouping (2026-08-19 file-sprawl consolidation).

# Migrated from data/rules.yml EACH_WITH_OBJECT.
Law.define(:EACH_WITH_OBJECT) do
  source "Ruby Style Guide / RuboCop Style/EachWithObject"
  severity :warn
  languages %i[ruby]
  detect { |line| line.match?(/\.(inject|reduce)\(\s*(\{\s*\}|\[\s*\])\s*\)/) }
  fix "Only when the argument is a literal {} or [] that the block mutates in place. Do NOT rewrite reduce/inject whose block returns the next accumulator (a rebuilt string, a running total, a folded hash) — each_with_object discards that return value and the fold becomes a no-op. If in doubt, leave reduce alone."
  bad  "items.inject({}) { |h, i| h[i] = 1; h }"
  good "items.each_with_object({}) { |i, h| h[i] = 1 }"
end

# FEW_ARGUMENTS lives once, in the registry (universal_rules.rb): it splits
# the parameter list and counts only positionals, where this regex counted
# keywords, defaults, splats and blocks as arguments too — a def with four
# keyword args is the fix, not the offence. KEYWORD_ARGS folds into it: two
# ids counted the same parameter list, one at :warn and one at :info, so the
# same def carried two findings that differed only in name.

# Migrated from data/rules.yml FROZEN_STRING_LITERAL.
Law.define(:FROZEN_STRING_LITERAL) do
  source "Ruby Style Guide / RuboCop Style/FrozenStringLiteralComment"
  severity :warn
  languages %i[ruby]
  scope :file
  # Its subject IS a comment, so it has to be allowed to see one. Without this,
  # considered_text blanks line 1 before the detector reads it and the file looks
  # like it starts with a newline — which is exactly what the lookahead is
  # testing for. Measured before the fix: 423 of 423 files under MASTER/lib that
  # carry the magic comment were flagged as missing it. A law that fires on every
  # file it should pass is indistinguishable from one nobody wired up.
  reads_comments true
  # A shebang may precede it, and Ruby still honours it — proved rather than
  # assumed: a file whose line 1 is #!/usr/bin/env ruby and line 2 is the magic
  # comment freezes its literals, and the same file without the comment does not.
  # Anchored at \A this flagged all 24 executables in OPENBSD, RAILS/gates and
  # MASTER/tools that carry the comment in the only place a shebang leaves for it.
  detect { |text| !text.match?(/\A(?:#![^\n]*\n)?# frozen_string_literal/) }
  fix "Add '# frozen_string_literal: true' as the first line, or the line after a shebang."
  bad <<~X
    require "json"
  X
  good <<~X
    # frozen_string_literal: true
  X
end

# Migrated from data/rules.yml GUARD_CLAUSE.
Law.define(:GUARD_CLAUSE) do
  source "Ruby Style Guide / RuboCop Style/GuardClause"
  severity :info
  languages %i[ruby]
  scope :file
  # No /m, and [^\n]* rather than .*: with /m the `.` after `def \w+` matched
  # newlines, so the pattern swallowed the whole file and backtracked — any
  # file containing a def, a later `if`, a later `else` and a trailing `end`
  # matched, and scope :file reports every hit at line 1. It flagged 321 of
  # 2,381 authored Ruby files, each pointing at frozen_string_literal. The
  # lookahead keeps the body inside one method. The 3-line fixtures below are
  # too small to exhibit that, which is why prove! never caught it.
  # The if and its else must be one block. Allowing any non-def line between
  # them let the match cross an `end` and stitch a method's first `if` — which
  # already returns early — to the `else` of a later, unrelated one. signals.rb
  # was flagged for exactly that: on_int opens with a guard and the pattern
  # reached past its `end` to the next conditional.
  #
  # The backreference pins `else` and `end` to the `if`'s own indent and every
  # line between to a deeper one, so a closed block cannot be crossed. 24 files
  # to 18, and what remains is a method whose whole body is the conditional —
  # which is what the fixtures show and what a guard clause replaces.
  # "A method whose whole body is the conditional" is what the paragraph above
  # claims and what a guard clause can actually replace, but the pattern only
  # anchored the `if` to the first line and never checked the method ended
  # there. display_ok opens with `if streamed` and then prints five footers
  # after the block; returning early from either arm would skip them, so there
  # is no guard clause to flatten it to. The def's own `end` has to follow the
  # conditional's.
  detect do |text|
    text.match?(/^([ \t]*)def \w+[^\n]*\n\1[ \t]+if [^\n]+\n(?:(?!\1(?:def|end)\b)[^\n]*\n)*?\1[ \t]+else\n(?:(?!\1(?:def|end)\b)[^\n]*\n)*?\1[ \t]+end\n\1end\b/)
  end
  fix "Flatten to: return ... unless condition"
  bad <<~X
    def go(x)
      if x
        run
      else
        nil
      end
    end
  X
  good <<~X
    def go(x)
      return unless x
      run
    end
  X
end

# HASH_FETCH lives once, in the registry (ruby_rules.rb): it excludes
# memoization (`||=`), the string-or-symbol dual-key fallback in either key
# order, and comparison chains that merely contain a bracket access — none
# of which are fetch candidates, all of which this bare regex flagged.

# Migrated from data/rules.yml IMMUTABLE.
Law.define(:IMMUTABLE) do
  source "Effective Java — minimize mutability (Joshua Bloch); FP"
  severity :info
  languages %i[ruby]
  detect { |line| line.match?(/^\s*[A-Z][A-Z_]*\s*=\s*(?:\[[^\]\n]*\]|\{[^}\n]*\})\s*$/) }
  fix "Freeze collections. Use frozen/const by default."
  bad  "COLORS = [:red, :blue]"
  good "COLORS = [:red, :blue].freeze"
end

# Migrated from data/rules.yml KERNEL_COERCION. The registry twin learned
# that `(h[k] || []) << x` is append-to-default, not a coercion candidate —
# the `(?!\s*<<)` guard moved here with the retirement.
Law.define(:KERNEL_COERCION) do
  source "Ruby Style Guide — Integer()/Float() over to_i/to_f"
  severity :info
  languages %i[ruby]
  path_exclude %r{/review/scan/rules/}
  # The `|| []` arm left. The fix line names one substitution — the explicit
  # nil-ternary — and `x || []` is not that: Array() splats a Hash into pairs
  # and wraps a String, so swapping it in is a behaviour change wherever the
  # value is not already an array or nil. The rule's own `good` fixture carries
  # two surviving `|| []` forms, which is the rule agreeing with itself.
  detect { |line| line.match?(/(\w+)\s*\.\s*nil\?\s*\?\s*\[\]\s*:\s*\1/) }
  fix "Use Array(x) instead of x.nil? ? [] : x"
  bad  "list.nil? ? [] : list"
  good <<~X
    Array(list)
    held = index[key] || [] << entry
    errors[key] ||= []
  X
end

# KEYWORD_ARGS was deleted here on 2026-08-21 — folded into FEW_ARGUMENTS
# (see that entry above): two ids, one detector concept, double findings.

# law/rails.rb was deleted here on 2026-08-21. Its four rules — FIND_EACH,
# N_PLUS_ONE, NO_UPDATE_ATTRIBUTE, PLUCK_OVER_MAP — declared `languages
# %i[rails]`, and FILE_LANGUAGE_MAP produces no such language: every .rb
# file is "ruby". The four laws had never matched a single file; the
# registry twins (ruby_rules.rb, universal_rules.rb), path-scoped to
# /app/, were the only live implementations all along — the inert-config
# defect, in the constitution itself. They live once, in the registry.

# Migrated from data/rules.yml MIGRATION_ADD_REFERENCE_NO_FK.
Law.define(:MIGRATION_ADD_REFERENCE_NO_FK) do
  source "Rails migrations — foreign_key: true (Strong Migrations)"
  severity :error
  languages %i[ruby]
  path "/db/migrate/"
  detect { |line| line.match?(/add_reference(?!.*foreign_key:)/) }
  fix "Add `foreign_key: true` to enforce referential integrity."
  bad  "add_reference :posts, :user"
  good "add_reference :posts, :user, foreign_key: true"
end

# Migrated from data/rules.yml MIGRATION_FIND_OR_CREATE_BY.
Law.define(:MIGRATION_FIND_OR_CREATE_BY) do
  source "Rails best practice — find_or_create_by races"
  severity :warn
  languages %i[ruby]
  path "/db/migrate/"
  detect { |line| line.match?(/find_or_create_by/) }
  fix "Back find_or_create_by with a unique index to prevent duplicates."
  bad  "Role.find_or_create_by(name: 'admin')"
  good "Role.create!(name: 'admin')"
end

# Migrated from data/rules.yml MIGRATION_REMOVE_COLUMN.
Law.define(:MIGRATION_REMOVE_COLUMN) do
  source "Strong Migrations — safe column removal (Andrew Kane)"
  severity :error
  languages %i[ruby]
  path "/db/migrate/"
  # Whether the migration documents its path is a question about the migration,
  # not about the line. amber's convert_money_to_ore does the safe thing eight
  # times — add_column, backfill with an UPDATE, then remove_column — and a
  # line-scoped detector reported all eight removals as unsafe while the
  # backfill sat three lines above each one.
  scope :file
  detect do |text|
    text.match?(/\bremove_column\b/) &&
      !text.match?(/\b(?:add_column|rename_column|update_all|execute)\b/)
  end
  fix "Document safety/backfill path before removing a column."
  bad <<~X
    def up
      remove_column :users, :legacy
    end
  X
  good <<~X
    def up
      add_column :users, :name, :string
      execute "UPDATE users SET name = legacy"
      remove_column :users, :legacy
    end
  X
end

# Migrated from data/rules.yml PERCENT_LITERAL.
Law.define(:PERCENT_LITERAL) do
  source "Ruby Style Guide — %w/%i array literals"
  severity :info
  languages %i[ruby]
  detect { |line| line.match?(/\[:[a-z_]+,\s*:[a-z_]+,\s*:[a-z_]+/) }
  fix "Use %i[a b c] for symbol arrays."
  bad  "[:a, :b, :c]"
  good "%i[a b c]"
end

# Migrated from data/rules.yml RATE_LIMITING_MISSING.
Law.define(:RATE_LIMITING_MISSING) do
  source "OWASP API Security — rate limiting"
  severity :error
  languages %i[ruby]
  scope :file
  path "/app/controllers/"
  absent /rate_limit|throttle/
  detect { |text| text.match?(/(login|signup|sign_up|password|reset)/m) }
  fix "Add rate_limit/throttle to sensitive actions."
  bad <<~X
    def login
    end
  X
  good <<~X
    rate_limit to: 5, within: 1.minute
    def login
    end
  X
end

# Migrated from data/rules.yml RESCUE_ON_DEF.
Law.define(:RESCUE_ON_DEF) do
  source "Ruby Style Guide — rescue in method definitions"
  severity :info
  languages %i[ruby]
  path_exclude %r{/review/scan/rules/}
  scope :file
  # Same /m defect as GUARD_CLAUSE above: the pattern spanned unrelated methods,
  # gluing a def to a rescue hundreds of lines away and reporting it at line 1.
  # A def-level rescue is a `begin` on the line directly after the def, which is
  # what the bad fixture shows.
  # The begin has to BE the body, which is what "put rescue on the def" means.
  # Unanchored, this matched a begin/rescue guarding one statement at the top of
  # a method — visual_contract.rb wraps its `require "selenium-webdriver"` that
  # way and then does fifteen more lines. Hoisting that rescue to the def would
  # widen it to catch a LoadError from anywhere in the method, which is the
  # opposite of the tightening the rule is asking for.
  #
  # The backreference pins the begin's `end` and the def's `end` to their own
  # indents, so the block only matches when nothing follows it.
  detect do |text|
    text.match?(/^([ \t]*)def \w+[^\n]*\n\1[ \t]+begin\n(?:(?!\1[ \t]*(?:def|end)\b)[^\n]*\n)*?\1[ \t]+rescue[^\n]*\n(?:(?!\1[ \t]*def )[^\n]*\n)*?\1[ \t]+end\n\1end\b/)
  end
  fix "Put rescue directly on the def block."
  bad <<~X
    def go
      begin
        run
      rescue Foo
      end
    end
  X
  good <<~X
    def go
      run
    rescue Foo
      nil
    end
  X
end

# Migrated from data/rules.yml RUBY_BLOCK_DELIMITER.
Law.define(:RUBY_BLOCK_DELIMITER) do
  source "Ruby Style Guide / RuboCop Style/BlockDelimiters"
  severity :info
  languages %i[ruby]
  path_exclude %r{/review/scan/rules/}
  detect { |line| line.match?(/\bdo\b\s*(\|[^|]*\|)?[^\n]*\bend\s*$/) }
  fix "Single-line block on one line -> use { }. Reserve do/end for multi-line."
  bad  "list.each do |x| puts x end"
  good "list.each { |x| puts x }"
end

# Migrated from data/rules.yml RUBY_CAMEL_CLASS.
Law.define(:RUBY_CAMEL_CLASS) do
  source "Ruby Style Guide / RuboCop Naming/ClassAndModuleCamelCase"
  severity :warn
  languages %i[ruby]
  path_exclude %r{/review/scan/rules/}
  # A declaration ends the line, or continues only into a superclass. A sentence
  # keeps going, and prose in a heredoc is not blanked the way a comment is:
  # "module into shared/vendor/javascript, or pin it preload: false and" is a
  # wrapped line of advice inside importmap_external_hosts_examples.rb, read as
  # a module named `into`.
  detect { |line| line.match?(/^\s*(class|module)\s+([a-z]\w*|[A-Z]\w*_\w*)\s*(?:<\s*[\w:]+\s*)?$/) }
  fix "Rename to CamelCase: class Album_store -> class AlbumStore."
  bad  "class Album_store"
  good "class AlbumStore"
end

# Migrated from data/rules.yml RUBY_NUMERIC_UNDERSCORE.
Law.define(:RUBY_NUMERIC_UNDERSCORE) do
  source "Ruby Style Guide / RuboCop Style/NumericLiterals"
  severity :info
  languages %i[ruby]
  path_exclude %r{/review/scan/rules/}
  # A long run of digits inside a string is not a numeric literal. Unmasked, this
  # read a port out of "http://127.0.0.1:38182/", an ffmpeg filter's
  # sample_rates=44100, the hex in '#010203', and the digits in this rule's own
  # fix line — 107 findings of which 81 were quoted text. Strings, regexes and
  # trailing comments are blanked before the digits are counted, and a preceding
  # colon or word character rules out a port or an identifier.
  detect do |line|
    masked = line.dup
    masked.gsub!(/"(?:[^"\\]|\\.)*"/) { |m| "\0" * m.length }
    masked.gsub!(/(?:[^\w?\\]|\A)'(?:[^'\\]|\\.)*'/) { |m| "\0" * m.length }
    masked.gsub!(%r{/(?:[^/\\\n]|\\.)+/}) { |m| "\0" * m.length }
    if (at = masked.index(/(?<!['"\0])#/))
      masked[at..] = "\0" * (masked.length - at)
    end
    # `=` joins the lookbehind. A heredoc has no quotes to blank, so the ffmpeg
    # graphs in mix_recipes.rb arrived unmasked and every `sample_rates=44100`
    # and `equalizer=f=12000` read as a Ruby literal — 23 findings whose fix
    # would have written `44_100` into a filter string and broken the render.
    # Ruby spaces its assignment; a `=` flush against the digits is a config
    # token in some other language.
    masked.match?(/(?<![\d_.:\w=])\d{5,}(?![\d_])/)
  end
  fix "Group digits in threes: one million is 1_000_000."
  bad  "max = 1000000"
  good "max = 1_000_000"
end

# Migrated from data/rules.yml RUBY_SNAKE_METHODS.
Law.define(:RUBY_SNAKE_METHODS) do
  source "Ruby Style Guide / RuboCop Naming/MethodName"
  severity :warn
  languages %i[ruby]
  path_exclude %r{/review/scan/rules/}
  detect { |line| line.match?(/\bdef\s+[a-z][a-z0-9_]*[A-Z]/) }
  fix "Rename to snake_case: def fetchAlbum -> def fetch_album."
  bad  "def fetchAlbum"
  good "def fetch_album"
end

# Migrated from data/rules.yml RUBY_SYMBOL_TO_PROC.
Law.define(:RUBY_SYMBOL_TO_PROC) do
  source "Ruby Style Guide / RuboCop Style/SymbolProc"
  severity :info
  languages %i[ruby]
  path_exclude %r{/review/scan/rules/}
  detect { |line| line.match?(/\{\s*\|(\w+)\|\s*\1\.[a-z_]+\s*\}/) }
  fix "Collapse { |x| x.name } -> (&:name)."
  bad  "names = users.map { |u| u.name }"
  good "names = users.map(&:name)"
end

# Migrated from data/rules.yml RUBY_SCREAMING_CONST, which declared only a
# detect_semantic and was therefore the one RUBY_* naming rule that could not
# fire: the semantic prompt drops info severity, so it sat in rule_reach's
# unreachable set while its six siblings ran lexically.
#
# The reason it was left semantic is the exception, not the rule: a constant
# holding a *type* is CamelCase by convention — Entry = Data.define(...),
# Finding = Struct.new(...) — and this tree uses that shape everywhere. So the
# detector asks what is on the right, not only what is on the left, and an
# alias of another constant is spared for the same reason.
Law.define(:RUBY_SCREAMING_CONST) do
  source "Ruby Style Guide / RuboCop Naming/ConstantName"
  severity :info
  languages %i[ruby]
  path_exclude %r{/review/scan/rules/}
  detect do |line|
    match = line.match(/^\s*([A-Z][A-Za-z0-9]*)\s*=(?!=|~|>)\s*(.*)$/)
    next false unless match && match[1].match?(/[a-z]/)
    next false if match[2].match?(/\A(Struct\.new|Data\.define|Class\.new|Module\.new)/)

    !match[2].match?(/\A[A-Z][\w:]*\s*\z/)
  end
  fix "Scream a constant that holds a value: MaxRetries = 3 -> MAX_RETRIES = 3."
  bad  "MaxRetries = 3"
  good "MAX_RETRIES = 3"
end

# RUBY_TERNARY_NOT_NESTED lives once, in the registry (cosmetic_rules.rb):
# it parses with Prism and asks the AST whether a ternary branch holds a
# ternary. This regex counted `?` and `:` characters, so a string literal
# containing a question mark or a hash colon made any ternary "nested".

# Migrated from data/rules.yml SAFE_NAVIGATION. The registry twin learned
# that `a && a.count > b` is a comparison, not a nil-guard to collapse —
# `a&.count > b` raises on nil where the original short-circuits. The
# comparison/ternary guard moved here with the retirement.
Law.define(:SAFE_NAVIGATION) do
  source "Ruby Style Guide / RuboCop Style/SafeNavigation"
  severity :warn
  languages %i[ruby]
  path_exclude %r{/review/scan/rules/}
  detect { |line| line.match?(/(\w+)\s*&&\s*\1\.\w+/) && !line.match?(/[!=<>]=|[<>]|\?\s*\w/) }
  fix "Rewrite to x&.foo&.bar"
  bad  "user && user.name"
  good <<~X
    user&.name
    ok if list && list.size > 3
  X
end

# Migrated from data/rules.yml SINGLE_PRIVATE_SECTION.
Law.define(:SINGLE_PRIVATE_SECTION) do
  source "Ruby Style Guide / RuboCop Style/AccessModifierDeclarations"
  severity :info
  languages %i[ruby]
  detect { |line| line.match?(/private\s+:\w+/) }
  fix "Use a single 'private' keyword with methods below it."
  bad  "private :helper"
  good <<~X
    private

    def helper; end
  X
end

# Migrated from data/rules.yml STRICT_LOADING_MISSING.
Law.define(:STRICT_LOADING_MISSING) do
  source "Rails strict_loading — N+1 prevention (Rails Guides)"
  severity :info
  languages %i[ruby]
  scope :file
  path "/app/models/"
  absent /\bstrict_loading_by_default\b/
  # The base class is where the default is set, and subclasses inherit it.
  # Matching `< ApplicationRecord` too asked all thirty of amber's models to
  # restate a setting RAILS/shared/app/models/application_record.rb already
  # makes — the same shape as the `dependent:` census in proposals.yml, which
  # counted declarations whose behaviour comes from the class above them.
  detect { |text| text.match?(/class\s+\w+\s+<\s+ActiveRecord::Base\b/m) }
  fix "Add `self.strict_loading_by_default = true` to surface missing eager-loads."
  bad <<~X
    class ApplicationRecord < ActiveRecord::Base
    end
  X
  good <<~X
    class ApplicationRecord < ActiveRecord::Base
      self.strict_loading_by_default = true
    end
  X
end

# Migrated from data/rules.yml TRANSFORM_KEYS.
Law.define(:TRANSFORM_KEYS) do
  source "Ruby idiom — Hash#transform_keys/values"
  severity :info
  languages %i[ruby]
  detect { |line| line.match?(/\.each_with_object\(\{\}\)\s*\{\s*\|\(k,\s*v\),\s*h\|/) }
  fix "Use .transform_values { |v| ... }"
  bad  "h.each_with_object({}) { |(k, v), h| h[k] = v * 2 }"
  good "h.transform_values { |v| v * 2 }"
end

# Migrated from data/rules.yml USE_THEN.
Law.define(:USE_THEN) do
  source "Ruby idiom — Object#then (yield_self) for pipelines"
  severity :info
  languages %i[ruby]
  path_exclude %r{/review/scan/rules/}
  scope :file
  # The same defect GUARD_CLAUSE carried and had fixed above: `/m` makes `.`
  # match newlines, so `\(.*\)` ran to the last paren in the file and any file
  # holding an assignment and a later call matched. scope :file then reports it
  # at line 1, so every hit pointed at frozen_string_literal.
  #
  # The pair has to be adjacent to be a pipeline — that is the whole idea the
  # rule is about, and it is what the fixtures show. [^\n]* keeps the call on
  # its own line.
  # The binding has to die at that second call. Adjacency alone says nothing
  # about whether the name is used again, and in this tree it usually is:
  # DiffStager builds an entry, persists it, and then publishes and returns
  # three of its fields; SessionCapture parses, writes, and then feeds the same
  # capture to three more updaters. Chaining those drops a variable the rest of
  # the method needs — applying this rule to its own eight findings introduced
  # three NameErrors, which is how the check below was earned.
  #
  # `then` is only an improvement where the intermediate exists to be handed on
  # once. Everything after the pair, down to the end of the enclosing block, has
  # to be free of the name.
  detect do |text|
    text.enum_for(:scan, /^([ \t]*)(\w+)\s*=\s*\w+\([^\n]*\)\n[ \t]*\w+\(\2\)/).any? do
      match = Regexp.last_match
      indent = match[1].length
      rest = text[match.end(0)..].to_s.lines
      stop = rest.index { |line| !line.strip.empty? && line[/\A[ \t]*/].length < indent }
      (stop ? rest[0...stop] : rest).join.match?(/\b#{Regexp.escape(match[2])}\b/) == false
    end
  end
  fix "Chain with .then { |r| next_step(r) }"
  bad <<~X
    r = parse(src)
    render(r)
  X
  good <<~X
    parse(src).then { |r| render(r) }
  X
end

# Polished Ruby Programming (Jeremy Evans), ch. 1-2: reopening a core class
# changes it for every library in the process — the least polite thing a
# codebase can do. A refinement or a helper module carries the same behaviour
# without the blast radius.
Law.define(:MONKEY_PATCH_CORE) do
  source "Polished Ruby Programming (Jeremy Evans) — core class hygiene"
  severity :warn
  languages %i[ruby]
  path_exclude %r{/test/|/spec/}
  detect { |line| line.match?(/\A\s*class\s+(?:String|Array|Hash|Integer|Float|Symbol|Object|Kernel|NilClass|Numeric|Range|Time|Comparable|Enumerable)\s*\z/) }
  fix "Use a refinement, a helper module, or a wrapping method instead of reopening the core class."
  bad  "class String"
  good "module StringHelpers"
end

# Polished Ruby Programming: __dir__ is the modern spelling and survives
# symlinks the way the old idiom does not.
Law.define(:DIRNAME_FILE) do
  source "Polished Ruby Programming (Jeremy Evans) — prefer __dir__"
  severity :info
  languages %i[ruby]
  detect { |line| line.match?(/File\.dirname\(__FILE__\)/) }
  fix "Use __dir__."
  bad  "File.expand_path(File.dirname(__FILE__))"
  good "File.expand_path(__dir__)"
end
