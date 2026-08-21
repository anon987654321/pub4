# frozen_string_literal: true

module Master
  module Review
    module Scan
      module Rules

        # Retired registry twins — each lives once, in law/:
        #   MIGRATION_ADD_REFERENCE_NO_FK, MIGRATION_FIND_OR_CREATE_BY, MIGRATION_REMOVE_COLUMN, PERCENT_LITERAL
        #   RATE_LIMITING_MISSING, STRICT_LOADING_MISSING, TRANSFORM_KEYS
        # (test_scan_rule_contracts proves each reaches findings through the bridge).

        # SINGLE_PRIVATE_SECTION lives once, in law/ruby.rb — fixtures attached, any narrowing
        # this version had learned ported there (2026-08-21 twin retirement).

        # principle_map: strong_parameters (detects mass_assignment_risk). Two
        # distinct failures, one rule: permit! waives the whitelist wholesale,
        # and a raw params[] reaching a mass-assignment sink never had one.
        # Scoped to /app/ rather than /app/controllers/ because a service or
        # model object handed the params hash carries the same risk.
        RuleDSL.rule :STRONG_PARAMETERS,
          severity: :error, tags: %i[SECURITY], applies_to: %i[ruby],
          description: "mass assignment goes through explicitly permitted attributes" do |src, path:|
          next [] unless path.include?("/app/")

          blanket = scan_lines(src, /\.permit!/,
            message: "permit! whitelists every attribute — name the permitted attributes instead")
          raw = scan_lines(src,
            /\.(?:new|create!?|update!?|update_attributes!?|assign_attributes)\(\s*params\[/,
            message: "raw params[] reaches mass assignment — route it through require(...).permit(...)")
          blanket + raw
        end

        # EACH_WITH_OBJECT lives once, in law/ruby.rb — fixtures attached, any narrowing
        # this version had learned ported there (2026-08-21 twin retirement).

        # KERNEL_COERCION lives once, in law/ruby.rb — fixtures attached, any narrowing
        # this version had learned ported there (2026-08-21 twin retirement).

        RuleDSL.rule :HASH_FETCH,
          severity: :info, tags: %i[READABILITY], applies_to: %i[ruby],
          description: "prefer Hash#fetch over [] with ||" do |src, path:|
          next [] if path.to_s.include?("/review/scan/rules/")
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

        # IMMUTABLE lives once, in law/ruby.rb — fixtures attached, any narrowing
        # this version had learned ported there (2026-08-21 twin retirement).

        RuleDSL.rule :FIND_EACH,
          severity: :warning, tags: %i[PERFORMANCE], applies_to: %i[ruby],
          description: "use find_each for batch processing" do |src, path:|
          next [] unless path.match?(%r{/app/|/spec/|/test/})
          scan_lines(src, /\.(all\.each|where\(.*\)\.each)\b/,
            message: "unbounded .all.each — use find_each(batch_size: N)")
        end

        RuleDSL.rule :NO_UPDATE_ATTRIBUTE,
          severity: :error, tags: %i[DATA_INTEGRITY], applies_to: %i[ruby],
          description: "replace update_attribute with update!" do |src, path:|
          next [] unless path.match?(%r{/app/|/spec/|/test/})
          scan_lines(src, /\.update_attribute\(/, message: "update_attribute skips validations — use update!")
        end

        RuleDSL.rule :PLUCK_OVER_MAP,
          severity: :info, tags: %i[PERFORMANCE], applies_to: %i[ruby],
          description: "prefer pluck over map for single columns" do |src, path:|
          next [] unless path.match?(%r{/app/|/spec/|/test/})
          scan_lines(src, /\.\w+\.map\(&:\w+\)/, message: "use pluck(:column) to avoid loading full objects")
        end

        # KEYWORD_ARGS was deleted here on 2026-08-21 — folded into FEW_ARGUMENTS
        # (universal_rules.rb): two ids counted the same parameter list, one at
        # :warn and one at :info, and every 3+-positional def carried both.

        RuleDSL.rule :DEAD_CODE,
          severity: :warning, tags: %i[CLEAN_CODE], applies_to: %i[ruby],
          description: "eliminate unreachable code" do |src, path:|
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

        RuleDSL.rule :TRAILING_COMMAS,
          severity: :info, tags: %i[STYLE], applies_to: %i[ruby],
          description: "trailing commas in multi-line collections" do |src, path:|
          src.each_line.with_index(1).filter_map do |line, number|
            next unless line.match?(/^\s*"[^"]+",?\s*$/)
            next if line.match?(/,\s*$/)

            finding(line: number, message: "missing trailing comma in multi-line collection")
          end
        end

      end
    end
  end
end
