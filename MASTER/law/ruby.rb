# frozen_string_literal: true

# External practice sources represented here are deliberate inputs, not a second authority:
# RuboCop Ruby Style Guide (live guide); RuboCop Rails Style Guide; Fowler, Refactoring, 2nd ed. (2018);
# Martin, Clean Code, 2nd ed. (2025); Evans, Polished Ruby Programming, 2nd ed. (2026, Ruby 4.0).
# Mechanical style belongs to RuboCop; these Laws cover project-specific semantics, safety and refactoring proof.
# law/ruby.rb — every ruby law, one Law.define per law.
Law.define(:EACH_WITH_OBJECT) do
  source "Ruby Style Guide / RuboCop Style/EachWithObject"
  detect { |line| line.match?(/\.(inject|reduce)\(\s*(\{\s*\}|\[\s*\])\s*\)/) }
  fix "Only when the argument is a literal {} or [] that the block mutates in place. Do NOT rewrite reduce/inject whose block returns the next accumulator (a rebuilt string, a running total, a folded hash) — each_with_object discards that return value and the fold becomes a no-op. If in doubt, leave reduce alone."
  bad  "items.inject({}) { |h, i| h[i] = 1; h }"
  good "items.each_with_object({}) { |i, h| h[i] = 1 }"
end

# FEW_ARGUMENTS lives once, in the registry (universal_laws.rb): it splits
# the parameter list and counts only positionals, where this regex counted
# keywords, defaults, splats and blocks as arguments too — a def with four
# keyword args is the fix, not the offence. KEYWORD_ARGS folds into it: two
# ids counted the same parameter list, one at :warn and one at :info, so the
# same def carried two findings that differed only in name.

Law.define(:FROZEN_STRING_LITERAL) do
  source "Ruby Style Guide / RuboCop Style/FrozenStringLiteralComment"
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
  # Anchored at \A this flagged all 24 executables in OPENBSD, RAILS/checks and
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

Law.define(:GUARD_CLAUSE) do
  source "Ruby Style Guide / RuboCop Style/GuardClause"
  scope :file
  # No /m, and [^\n]* rather than .*: with /m the `.` after `def \w+` matched
  # newlines, so the pattern swallowed the whole file and backtracked — any
  # file containing a def, a later `if`, a later `else` and a trailing `end`
  # matched, and scope :file reports every hit at line 1. It flagged 321 of
  # 2,381 authored Ruby files, each pointing at frozen_string_literal. The
  # lookahead keeps the body inside one method. The original fixture was
  # too permissive to exercise the terminal-branch requirement, so prove! did not
  # catch the detector/fixture mismatch until the detector was tightened.
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
    match = text.match(/^([ \t]*)def \w+[^\n]*\n\1[ \t]+if [^\n]+\n(?:(?!\1(?:def|end)\b)[^\n]*\n)*?\1[ \t]+else\n(?:(?!\1(?:def|end)\b)[^\n]*\n)*?\1[ \t]+end\n\1end\b/)
    next false unless match

    branches = match[0].split(/^\s+else\s*$/)
    branches.size == 2 &&
      branches.all? { |branch| branch.match?(/\b(?:return|redirect_to|render|head|raise)\b/) }
  end
  fix "Flatten to: return ... unless condition"
  bad <<~X
    def go(x)
      if x
        return run
      else
        return nil
      end
    end
  X
  good <<~X
    def go(x)
      return unless x
      run
    end

    def pick(x)
      if x
        foo
      else
        bar
      end
    end
  X
end

# HASH_FETCH lives once, in the registry (ruby_laws.rb): it excludes
# memoization (`||=`), the string-or-symbol dual-key fallback in either key
# order, and comparison chains that merely contain a bracket access — none
# of which are fetch candidates, all of which this bare regex flagged.

Law.define(:IMMUTABLE) do
  source "Effective Java — minimize mutability (Joshua Bloch); FP"
  ask "Are mutable objects shared across threads or scopes where immutable data would be safer?"
  detect { |line| line.match?(/^\s*[A-Z][A-Z_]*\s*=\s*(?:\[[^\]\n]*\]|\{[^}\n]*\})\s*$/) }
  fix "Freeze collections. Use frozen/const by default."
  bad  "COLORS = [:red, :blue]"
  good "COLORS = [:red, :blue].freeze"
end

Law.define(:KERNEL_COERCION) do
  source "Ruby Style Guide — Integer()/Float() over to_i/to_f"
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
# registry twins (ruby_laws.rb, universal_laws.rb), path-scoped to
# /app/, were the only live implementations all along — the inert-config
# defect, in the constitution itself. They live once, in the registry.

Law.define(:MIGRATION_ADD_REFERENCE_NO_FK) do
  source "Rails migrations — foreign_key: true (Strong Migrations)"
  # A polymorphic reference names no single table, so it cannot carry a
  # foreign key; asking for one is asking for a migration that will not run.
  detect { |line| line.match?(/add_reference(?!.*(?:foreign_key:|polymorphic:\s*true))/) }
  fix "Add `foreign_key: true` to enforce referential integrity."
  bad  "add_reference :posts, :user"
  good "add_reference :posts, :user, foreign_key: true\nadd_reference :reactions, :reactable, polymorphic: true\n"
end

Law.define(:MIGRATION_FIND_OR_CREATE_BY) do
  source "Rails best practice — find_or_create_by races"
  detect { |line| line.match?(/find_or_create_by/) }
  fix "Back find_or_create_by with a unique index to prevent duplicates."
  bad  "Role.find_or_create_by(name: 'admin')"
  good "Role.create!(name: 'admin')"
end

Law.define(:MIGRATION_REMOVE_COLUMN) do
  source "Strong Migrations — safe column removal (Andrew Kane)"
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

Law.define(:PERCENT_LITERAL) do
  source "Ruby Style Guide — %w/%i array literals"
  detect { |line| line.match?(/\[:[a-z_]+,\s*:[a-z_]+,\s*:[a-z_]+/) }
  fix "Use %i[a b c] for symbol arrays."
  bad  "[:a, :b, :c]"
  good "%i[a b c]"
end

Law.define(:RATE_LIMITING_MISSING) do
  source "OWASP API Security — rate limiting"
  scope :file
  # A controller that includes the shared actions module inherits its limits,
  # and the module is scanned on its own.
  absent /rate_limit|throttle|include\s+(?:\w+::)*\w*(?:Sessions|Passwords|Registrations)Actions\b/
  # An action, not a word. Reading the file for "password" anywhere flagged
  # the authentication concern for calling reset_session, SSO provisioning for
  # generating a random password, and dating's base controller for a predicate
  # named vipps_login_available? — none of which is an endpoint. What takes a
  # credential is a controller or actions module named for sessions, passwords
  # or registrations, or an action whose own name says login, signup or reset.
  detect do |text|
    text.match?(/^\s*(?:class|module)\s+(?:\w+::)*\w*(?:Sessions|Passwords|Registrations|Signups?)(?:Controller|Actions)\b/) ||
      text.match?(/^\s*def\s+\w*(?:login|signup|sign_up|password|reset)\w*(?![\w?!])/)
  end
  fix "Add rate_limit/throttle to sensitive actions."
  bad <<~X
    def login
    end
  X
  good <<~X
    rate_limit to: 5, within: 1.minute
    def login
    end
    def vipps_login_available?
    end
  X
end

Law.define(:RESCUE_ON_DEF) do
  source "Ruby Style Guide — rescue in method definitions"
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

Law.define(:RUBY_BLOCK_DELIMITER) do
  source "Ruby Style Guide / RuboCop Style/BlockDelimiters"
  detect { |line| line.match?(/\bdo\b\s*(\|[^|]*\|)?[^\n]*\bend\s*$/) }
  fix "Single-line block on one line -> use { }. Reserve do/end for multi-line."
  bad  "list.each do |x| puts x end"
  good "list.each { |x| puts x }"
end

Law.define(:RUBY_CAMEL_CLASS) do
  source "Ruby Style Guide / RuboCop Naming/ClassAndModuleCamelCase"
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

Law.define(:RUBY_NUMERIC_UNDERSCORE) do
  source "Ruby Style Guide / RuboCop Style/NumericLiterals"
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
    masked.match?(/(?<![\w.:=])\d{5,}(?![\d_])/)
  end
  fix "Group digits in threes: one million is 1_000_000."
  bad  "max = 1000000"
  good "max = 1_000_000"
end

Law.define(:RUBY_SNAKE_METHODS) do
  source "Ruby Style Guide / RuboCop Naming/MethodName"
  detect { |line| line.match?(/\bdef\s+[a-z][a-z0-9_]*[A-Z]/) }
  fix "Rename to snake_case: def fetchAlbum -> def fetch_album."
  bad  "def fetchAlbum"
  good "def fetch_album"
end

Law.define(:RUBY_SYMBOL_TO_PROC) do
  source "Ruby Style Guide / RuboCop Style/SymbolProc"
  detect { |line| line.match?(/\{\s*\|(\w+)\|\s*\1\.[a-z_]+\s*\}/) }
  fix "Collapse { |x| x.name } -> (&:name)."
  bad  "names = users.map { |u| u.name }"
  good "names = users.map(&:name)"
end

#
# The reason it was left semantic is the exception, not the rule: a constant
# holding a *type* is CamelCase by convention — Entry = Data.define(...),
# Finding = Struct.new(...) — and this tree uses that shape everywhere. So the
# detector asks what is on the right, not only what is on the left, and an
# alias of another constant is spared for the same reason.
Law.define(:RUBY_SCREAMING_CONST) do
  source "Ruby Style Guide / RuboCop Naming/ConstantName"
  ask "Is a Ruby value constant named in a case other than SCREAMING_SNAKE_CASE?"
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

# RUBY_TERNARY_NOT_NESTED lives once, in the registry (cosmetic_laws.rb):
# it parses with Prism and asks the AST whether a ternary branch holds a
# ternary. This regex counted `?` and `:` characters, so a string literal
# containing a question mark or a hash colon made any ternary "nested".

Law.define(:SAFE_NAVIGATION) do
  source "Ruby Style Guide / RuboCop Style/SafeNavigation"
  detect { |line| line.match?(/(\w+)\s*&&\s*\1\.\w+/) && !line.match?(/[!=<>]=|[<>]|\?\s*\w/) }
  fix "Rewrite to x&.foo&.bar"
  bad  "user && user.name"
  good <<~X
    user&.name
    ok if list && list.size > 3
  X
end

Law.define(:SINGLE_PRIVATE_SECTION) do
  source "Ruby Style Guide / RuboCop Style/AccessModifierDeclarations"
  detect { |line| line.match?(/private\s+:\w+/) }
  fix "Use a single 'private' keyword with methods below it."
  bad  "private :helper"
  good <<~X
    private

    def helper; end
  X
end

Law.define(:STRICT_LOADING_MISSING) do
  source "Rails strict_loading — N+1 prevention (Rails Guides)"
  scope :file
  absent /\bstrict_loading_by_default\b/
  # The base class is where the default is set, and subclasses inherit it.
  # Matching `< ApplicationRecord` too asked all thirty of amber's models to
  # restate a setting RAILS/__shared/app/models/application_record.rb already
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

Law.define(:TRANSFORM_KEYS) do
  source "Ruby idiom — Hash#transform_keys/values"
  detect { |line| line.match?(/\.each_with_object\(\{\}\)\s*\{\s*\|\(k,\s*v\),\s*h\|/) }
  fix "Use .transform_values { |v| ... }"
  bad  "h.each_with_object({}) { |(k, v), h| h[k] = v * 2 }"
  good "h.transform_values { |v| v * 2 }"
end

Law.define(:USE_THEN) do
  source "Ruby idiom — Object#then (yield_self) for pipelines"
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
  # three of its fields. Chaining that drops a variable the rest of
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
  source "Polished Ruby Programming, 2nd ed. (Jeremy Evans, 2026) — core class hygiene"
  detect { |line| line.match?(/\A\s*class\s+(?:String|Array|Hash|Integer|Float|Symbol|Object|Kernel|NilClass|Numeric|Range|Time|Comparable|Enumerable)\s*\z/) }
  fix "Use a refinement, a helper module, or a wrapping method instead of reopening the core class."
  bad  "class String"
  good "module StringHelpers"
end

# Clean Code — a class name is a noun that carries domain meaning. The
# deterministic floor under DOMAIN_LANGUAGE and LOAD_BEARING_NAMES, which
# otherwise only a model judges: a class or module named nothing but a noise
# word says only that code lives here, which the file already said. Bare names
# only — a domain qualifier redeems it, so UserManager and PaymentHelper pass
# and only standalone Manager, Utils, Misc do not. :info, narrow on purpose,
# because naming rules earn their width by not crying wolf.
Law.define(:NOISE_NAME) do
  source "Clean Code, 2nd ed. (Robert C. Martin, 2025) — class names are domain nouns, not noise words"
  detect do |line|
    line.match?(/\A\s*(?:class|module)\s+(?:[A-Z]\w*::)*(?:Manager|Utils?|Utilit(?:y|ies)|Misc|Stuff|Things?|Handlers|Foo|Bar|Baz|Te?mp)\b\s*(?:<.*)?\z/)
  end
  fix "Name it for the domain: what does it manage, hold, or do? SubscriptionBilling, not Manager."
  bad "class Manager"
  good "class SubscriptionBilling"
end

# Polished Ruby Programming: __dir__ is the modern spelling and survives
# symlinks the way the old idiom does not.
Law.define(:DIRNAME_FILE) do
  source "Polished Ruby Programming, 2nd ed. (Jeremy Evans, 2026) — prefer __dir__"
  detect { |line| line.match?(/File\.dirname\(__FILE__\)/) }
  fix "Use __dir__."
  bad  "File.expand_path(File.dirname(__FILE__))"
  good "File.expand_path(__dir__)"
end

# New (2026-09-17, book research). Fowler's Replace Loop with Pipeline:
# map-then-compact is two passes and a nil detour to say "give me the present
# values"; filter_map says it in one. RuboCop's Style/MapCompactWithFilterMap
# is disabled in both this tree's config and the omakase one, so nothing else
# flags it, and live sites existed in wardrobe_ai.rb and lib/trace at the time
# this landed. Only the single-line spelling: a map block spanning lines with
# .compact on its own line is invisible to a line detector, and chasing it
# costs more noise than the finding is worth.
Law.define(:FILTER_MAP) do
  source "Fowler, Refactoring, 2nd ed. (2018) — Replace Loop with Pipeline"
  # \b after compact so compact_blank, a different operation with no
  # filter_map twin, does not fire.
  detect { |line| line.match?(/\.map\s*(?:\{[^}]*\}|&:[\w!?]+)\s*\.compact\b/) }
  fix "Collapse map { }.compact into filter_map { } — one pass, no nil detour."
  bad  "ids = items.map { |i| i.external_id }.compact"
  good "ids = items.filter_map { |i| i.external_id }"
end

# New (2026-09-17, book research). Kleppmann: a stalled peer stalls you. An
# outbound HTTP call with no timeout hangs indefinitely on a silent peer, and
# on a 1-vCPU vm23 that is the box's signature outage shape — a hang, not a
# 5xx. DEGRADE_GRACEFULLY declared the principle with no timeout-shaped
# detector; this is one. File-scoped on purpose: `http = Net::HTTP.new(...)`
# followed by `http.open_timeout = 5` on its own line is the disciplined
# spelling a line detector would flag, so the question asked is whether the
# FILE ever names a timeout at all. A file naming one for a different call
# covers its HTTP too — a narrowing, recorded here, that keeps the honest
# idioms quiet.
Law.define(:EXPLICIT_HTTP_TIMEOUT) do
  source "Kleppmann, DDIA — timeouts on every outbound call"
  scope :file
  detect do |text|
    text.match?(/Net::HTTP\.(?:start|get)\b|URI\([^)]*\)\.open\b/) &&
      !text.match?(/(?:open_timeout|read_timeout|\btimeout:)/)
  end
  fix "Set open_timeout/read_timeout, or route the call through the shared HTTP boundary."
  bad  "Net::HTTP.start(uri.host, uri.port, use_ssl: true) { |h| h.request(req) }"
  good "Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 5, read_timeout: 10) { |h| h.request(req) }"
end

# New (2026-09-17, book research). A NOT NULL column added with no default
# breaks the previous code version during a rolling deploy: every insert
# between the migrate and the restart fails, and on this box a deploy already
# sheds amber and bsdports. The tree carried zero violations when this landed
# — every null: false had its default — so this is a guard on the exact shape
# of the most expensive failure class the deploys have, in the role
# MIGRATION_ADD_REFERENCE_NO_FK plays for references. add_column only:
# change_column_null is constrained after a backfill that lives in an earlier
# migration file, invisible from here, and flagging every one of those would
# cry wolf until the rule was ignored.
Law.define(:MIGRATION_NOT_NULL_NO_DEFAULT) do
  source "Kleppmann, DDIA — schema evolution under rolling deploy"
  detect do |line|
    line.match?(/\badd_column\b/) && line.match?(/null:\s*false/) && !line.match?(/default:\s/)
  end
  fix "Give the column a default:, or backfill in one migration and constrain in the next."
  bad  "add_column :posts, :kind, :string, null: false"
  good "add_column :posts, :kind, :string, null: false, default: \"post\""
end

module Master
  module Review
    module Scan
      module Laws

        # Assignment/branch/condition counts for one method, for ABC size.
        #
        # A module method rather than a lambda inside the rule block: counting
        # them in place put the case arms five levels deep — rule block, walk
        # lambda, def check, inner lambda, case — and LINEARITY caps nesting at
        # four. The rule that reported it is defined in this file, so the file
        # was failing the law it declares.
        #
        # Flat here on purpose: one guard, one dispatch to a lookup, no nesting
        # to reintroduce.
        module RubyRuleSupport
          ASSIGNMENT_NODES = %i[
            LocalVariableWriteNode InstanceVariableWriteNode ClassVariableWriteNode
            GlobalVariableWriteNode ConstantWriteNode LocalVariableOperatorWriteNode
            InstanceVariableOperatorWriteNode MultiWriteNode
          ].freeze

          CONDITION_NODES = %i[
            IfNode UnlessNode WhileNode UntilNode CaseNode WhenNode AndNode OrNode RescueNode
          ].freeze

          # [assignments, branches, conditions] over the whole subtree.
          def self.abc_counts(node)
            counts = { a: 0, b: 0, c: 0 }
            visit(node, counts)
            [counts[:a], counts[:b], counts[:c]]
          end

          def self.visit(node, counts)
            node.child_nodes.compact.each do |child|
              next unless child.respond_to?(:child_nodes)

              counts[bucket(child)] += 1 if bucket(child)
              visit(child, counts)
            end
          end

          # A CallNode ending in `=` is an assignment, not a branch — attr
          # writers would otherwise inflate B for every setter call.
          def self.bucket(node)
            short = node.class.name.split("::").last.to_sym
            return :a if ASSIGNMENT_NODES.include?(short)
            return :c if CONDITION_NODES.include?(short)
            return unless short == :CallNode

            node.name.to_s.end_with?("=") ? :a : :b
          end

          # A multi-line array or hash whose last element is not followed by a
          # comma before the closing bracket. Percent literals are excluded
          # because %w[] and %i[] separate on whitespace, so a comma inside one
          # becomes part of an element.
          def self.unterminated_collection?(node, src)
            opening = node.opening_loc
            closing = node.closing_loc
            return false unless opening && closing && !node.elements.empty?
            return false if opening.slice.start_with?("%")

            last = node.elements.last.location
            return false unless last.end_line < closing.start_line
            # RuboCop's `comma` style wants no comma once two items share a line.
            return false if node.elements.each_cons(2).any? { |left, right| left.location.end_line == right.location.start_line }

            gap = src.byteslice(last.end_offset, closing.start_offset - last.end_offset).to_s
            !gap.sub(/#.*/, "").include?(",")
          end
        end

        # Retired registry twins — each lives once, in law/:
        #   MIGRATION_ADD_REFERENCE_NO_FK, MIGRATION_FIND_OR_CREATE_BY, MIGRATION_REMOVE_COLUMN, PERCENT_LITERAL
        #   RATE_LIMITING_MISSING, STRICT_LOADING_MISSING, TRANSFORM_KEYS
        # (test_scan_rule_contracts proves each reaches findings through the bridge).

        # SINGLE_PRIVATE_SECTION lives once, in law/ruby.rb — fixtures attached, any narrowing
        # this version had learned ported there (2026-08-21 twin retirement).

        # principle_map: strong_parameters (detects mass_assignment_risk). Two
        # distinct failures, one law: permit! waives the whitelist wholesale,
        # and a raw params[] reaching a mass-assignment sink never had one.
        # Scoped to /app/ rather than /app/controllers/ because a service or
        # model object handed the params hash carries the same risk.
        ::Law.define(:STRONG_PARAMETERS) do
          tags %i[SECURITY]
          fix "mass assignment goes through explicitly permitted attributes"
          bad "Post.create(params[:post])\n"
          good "Post.create(params.require(:post).permit(:title))\n"
          check do |src, path|
            next [] unless path.include?("/app/")

            blanket = scan_lines(src, /\.permit!/,
              message: "permit! whitelists every attribute — name the permitted attributes instead")
            raw = scan_lines(src,
              /\.(?:new|create!?|update!?|update_attributes!?|assign_attributes)\(\s*params\[/,
              message: "raw params[] reaches mass assignment — route it through require(...).permit(...)")
            blanket + raw
          end
        end

        # EACH_WITH_OBJECT lives once, in law/ruby.rb — fixtures attached, any narrowing
        # this version had learned ported there (2026-08-21 twin retirement).

        # KERNEL_COERCION lives once, in law/ruby.rb — fixtures attached, any narrowing
        # this version had learned ported there (2026-08-21 twin retirement).

        ::Law.define(:HASH_FETCH) do
          tags %i[READABILITY]
          fix "prefer Hash#fetch over [] with ||"
          bad "value = options[:size] || 10\n"
          good "value = options.fetch(:size, 10)\n"
          check do |src, path|
            src.each_line.with_index(1).filter_map do |line, n|
              stripped = line.strip
              next unless (m = stripped.match(/(@{0,2}\w+)\[:\w+\]\s*\|\|(?!=)/))
              var = Regexp.escape(m[1])
              # A genuine fetch-with-default candidate is `hash[:key] || <default>`
              # where <default> is a plain value, not another lookup. Excluded here,
              # none of which are fetch candidates: memoization (`||=`, handled by
              # the negative lookahead above); the string-or-symbol dual-key
              # fallback in either key order (`h[:k] || h["k"]` or
              # `h["k"] || h[:k]`); and a comparison chain that coincidentally
              # contains a bracket access (`a[:x] >= b[:x] ||`).
              next if stripped.match?(/#{var}\[:\w+\]\s*\|\|\s*#{var}\[/)
              next if stripped.match?(/#{var}\[["']\w+["']\]\s*\|\|\s*#{var}\[:\w+\]/)
              next if stripped.match?(/(?:>=|<=|==|!=)\s*#{var}\[:\w+\]\s*\|\|/)

              finding(line: n, message: "hash symbol lookup with fallback — prefer hash.fetch(:key, default)")
            end
          end
        end

        # IMMUTABLE lives once, in law/ruby.rb — fixtures attached, any narrowing
        # this version had learned ported there (2026-08-21 twin retirement).

        ::Law.define(:FIND_EACH) do
          tags %i[PERFORMANCE]
          fix "use find_each for batch processing"
          bad "  User.all.each { |u| u.touch }\n"
          good "  User.find_each(batch_size: 500) { |u| u.touch }\n"
          check do |src, path|
            next [] unless path.match?(%r{/app/|/spec/|/test/})
            scan_lines(src, /\.(all\.each|where\(.*\)\.each)\b/,
              message: "unbounded .all.each — use find_each(batch_size: N)")
          end
        end

        ::Law.define(:NO_UPDATE_ATTRIBUTE) do
          tags %i[DATA_INTEGRITY]
          fix "replace update_attribute with update!"
          bad "  user.update_attribute(:name, name)\n"
          good "  user.update!(name: name)\n"
          check do |src, path|
            next [] unless path.match?(%r{/app/|/spec/|/test/})
            scan_lines(src, /\.update_attribute\(/, message: "update_attribute skips validations — use update!")
          end
        end

        ::Law.define(:PLUCK_OVER_MAP) do
          tags %i[PERFORMANCE]
          fix "prefer pluck over map for single columns"
          example_path "/repo/RAILS/brgen/app/models/example.rb"
          bad "  ids = order.items.map(&:id)\n"
          good "  ids = order.items.pluck(:id)\n"
          check do |src, path|
            # pluck is ActiveRecord's; a plain Ruby array has no columns. The
            # guard was any /app/, /spec/ or /test/ path, so STUDIO's tool tests
            # were told to pluck from arrays.
            next [] unless path.match?(%r{(?:\A|/)RAILS/.*/(?:app|spec|test)/})
            scan_lines(src, /\.\w+\.map\(&:\w+\)/, message: "use pluck(:column) to avoid loading full objects")
          end
        end

        # KEYWORD_ARGS was deleted here on 2026-08-21 — folded into FEW_ARGUMENTS
        # (universal_laws.rb): two ids counted the same parameter list, one at
        # :warn and one at :info, and every 3+-positional def carried both.

        ::Law.define(:DEAD_CODE) do
          tags %i[CLEAN_CODE]
          fix "eliminate unreachable code"
          transform "remove_immediate_dead_code"
          bad "  return value\n  log(value)\n"
          good "  return value if done?\n  log(value)\n"
          check do |src, path|
            lines = src.lines
            lines.each_with_index.filter_map do |line, index|
              # Terminator at the line start only, and unconditional: `x = return_val`,
              # `return x if cond`, `raise unless y`, and a ternary all keep the next
              # line reachable, and `return_index` is not the keyword at all. Matching
              # a bare \b(return|raise)\b flagged every guard clause in the codebase.
              match = line.match(/\A(\s*)(return|exit|raise|throw)\b(.*)$/)
              next unless match

              indent, rest = match[1], match[3]
              next if rest.match?(/\b(if|unless)\b/) || rest.match?(/&&|\|\|/) || rest.include?("?")
              # A statement that continues (`raise "…" \`, a trailing comma or operator, an
              # open bracket) does not end on this line, so the next line is still part of it.
              next if rest.rstrip.match?(/[\\,(\[{+*\/-]\z/) || rest.count("([{") > rest.count(")]}")

              following = lines[index + 1]
              next unless following

              stripped = following.strip
              next if stripped.empty? || stripped.match?(/\A(end|else|elsif|when|in |rescue|ensure|[)\]}])/)
              # Only code at the same or deeper indent in the same block is unreachable;
              # a dedent means the terminator ended its block and the next line is not.
              next unless following[/\A */].length >= indent.length

              finding(line: index + 2, message: "unreachable code after #{line.strip}")
            end
          end
        end

        # ABC size, the one external-linter signal with no bespoke equivalent:
        # the 2026-08-13 overlap measurement (debt: scanner_overlaps_two_
        # installed_linters) found Metrics/AbcSize produced 13 of the 42
        # findings nothing here could see — the largest unique signal on
        # either side. Written bespoke per that entry's conclusion instead of
        # bridging rubocop per-file: sqrt(A²+B²+C²), counted from the AST,
        # never from line text, calibrated against rubocop on a shared file
        # (85.5 here vs 85.91 there for the same method).
        #
        # The THRESHOLD is the ratchet. At rubocop's default 17 the fleet
        # holds 560 findings — a flood that would bury the constitutional
        # ceilings recorded at 1/21/1/1 the same day. 40 catches the 24
        # worst (top: 85.5 in brgen's application_helper); walk it down as
        # they fall: 40 -> 30 (81) -> 25 (169) -> 17 (560).
        ::Law.define(:ABC_SIZE) do
          tags %i[COMPLEXITY]
          fix "method ABC size over the ratchet threshold — extract until the pieces name themselves"
          example_path "/repo/lib/example.rb"
          bad "def dense(x)\n" + Array.new(20) { |i| "  v#{i} = x.call(#{i}) if x.ok?(#{i})\n" }.join + "end\n"
          good "def calm(x)\n  y = x.call\n  y ? y.to_s : nil\nend\n"
          check do |src, path|
            result = Prism.parse(src)
            next [] if result.failure?

            findings = []
            walk = lambda do |node|
              next unless node.respond_to?(:child_nodes)
              if node.is_a?(Prism::DefNode)
                a, b, c = RubyRuleSupport.abc_counts(node)
                abc = Math.sqrt(a**2 + b**2 + c**2)
                if abc > 40
                  findings << finding(line: node.location.start_line,
                    message: "ABC size #{abc.round(1)} for ##{node.name} (A=#{a} B=#{b} C=#{c}, ratchet 40) — extract until the pieces name themselves")
                end
              end
              node.child_nodes.compact.each { |child| walk.call(child) }
            end
            walk.call(result.value)
            findings
          end
        end

        # Only array and hash literals, because those are the two the autofix
        # `add_trailing_commas` closes on — it matches a line opening with `]`
        # or `}`. The lexical detector this replaces matched any line holding
        # nothing but a quoted string, so it reported 496 findings across MASTER
        # of which the great majority were a method's last expression or an
        # assertion message, and the fixer would have touched none of them.
        ::Law.define(:TRAILING_COMMAS) do
          source "Ruby/JS style — trailing commas in multiline literals"
          ask "Does a multiline collection or argument list omit a trailing comma that stabilizes diffs?"
          tags %i[STYLE]
          fix "Add the trailing comma to multiline collections and argument lists."
          bad %(LIST = [\n  "one"\n]\n)
          good %(LIST = [\n  "one",\n]\n)
          check do |src, path|
            next [] unless %w[ruby].include?(language(path))
            next [] if Master::Fix::Scan::AstFixer::DeadCodeAndCommas.rubocop_forbids_trailing_comma?(path)

            parsed = Prism.parse(src)
            next [] if parsed.failure?

            collections = each_node(parsed.value, Prism::ArrayNode) + each_node(parsed.value, Prism::HashNode)
            collections.filter_map do |node|
              next unless RubyRuleSupport.unterminated_collection?(node, src)

              finding(line: node.closing_loc.start_line, message: "missing trailing comma in multi-line collection")
            end
          end
        end
      end
    end
  end
end
