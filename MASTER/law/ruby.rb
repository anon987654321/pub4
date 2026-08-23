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
  detect { |text| text.match?(/\A(?!# frozen_string_literal)/m) }
  fix "Add '# frozen_string_literal: true' as first line."
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
  detect do |text|
    text.match?(/^[ \t]*def \w+[^\n]*\n[ \t]*if [^\n]+\n(?:(?![ \t]*def )[^\n]*\n)*?[ \t]*else\n(?:(?![ \t]*def )[^\n]*\n)*?[ \t]*end[ \t]*$/)
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
  detect { |line| line.match?(/(\w+)\s*\.\s*nil\?\s*\?\s*\[\]\s*:\s*\1|(\w+)\s*\|\|\s*\[\](?!\s*<<)/) }
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
  detect { |line| line.match?(/remove_column/) }
  fix "Document safety/backfill path before removing a column."
  bad  "remove_column :users, :legacy"
  good "add_column :users, :name, :string"
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
  detect { |text| text.match?(/^[ \t]*def \w+[^\n]*\n[ \t]*begin\n(?:(?![ \t]*def )[^\n]*\n)*?[ \t]*rescue/) }
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
  detect { |line| line.match?(/^\s*(class|module)\s+([a-z]|[A-Z]\w*_)/) }
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
  detect { |line| line.match?(/[^\d_.]\d{5,}(?![\d_])/) }
  fix "Group digits in threes: 1000000 -> 1_000_000."
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
  detect { |text| text.match?(/class\s+\w+\s+<\s+(?:ApplicationRecord|ActiveRecord::Base)\b/m) }
  fix "Add `self.strict_loading_by_default = true` to surface missing eager-loads."
  bad <<~X
    class User < ApplicationRecord
    end
  X
  good <<~X
    class User < ApplicationRecord
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
  detect { |text| text.match?(/(\w+)\s*=\s*\w+\(.*\)\n\s*\w+\(\1\)/m) }
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
