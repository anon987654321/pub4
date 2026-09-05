# frozen_string_literal: true

module Master
  module Review
    module Scan
      module Rules

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
            return nil unless short == :CallNode

            node.name.to_s.end_with?("=") ? :a : :b
          end
        end

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
          fires: "  User.all.each { |u| u.touch }\n",
          does_not_fire: "  User.find_each(batch_size: 500) { |u| u.touch }\n",
          description: "use find_each for batch processing" do |src, path:|
          next [] unless path.match?(%r{/app/|/spec/|/test/})
          scan_lines(src, /\.(all\.each|where\(.*\)\.each)\b/,
            message: "unbounded .all.each — use find_each(batch_size: N)")
        end

        RuleDSL.rule :NO_UPDATE_ATTRIBUTE,
          severity: :error, tags: %i[DATA_INTEGRITY], applies_to: %i[ruby],
          fires: "  user.update_attribute(:name, name)\n",
          does_not_fire: "  user.update!(name: name)\n",
          description: "replace update_attribute with update!" do |src, path:|
          next [] unless path.match?(%r{/app/|/spec/|/test/})
          scan_lines(src, /\.update_attribute\(/, message: "update_attribute skips validations — use update!")
        end

        RuleDSL.rule :PLUCK_OVER_MAP,
          severity: :info, tags: %i[PERFORMANCE], applies_to: %i[ruby],
          fires: "  ids = order.items.map(&:id)\n",
          does_not_fire: "  ids = order.items.pluck(:id)\n",
          description: "prefer pluck over map for single columns" do |src, path:|
          next [] unless path.match?(%r{/app/|/spec/|/test/})
          scan_lines(src, /\.\w+\.map\(&:\w+\)/, message: "use pluck(:column) to avoid loading full objects")
        end

        # KEYWORD_ARGS was deleted here on 2026-08-21 — folded into FEW_ARGUMENTS
        # (universal_rules.rb): two ids counted the same parameter list, one at
        # :warn and one at :info, and every 3+-positional def carried both.

        RuleDSL.rule :DEAD_CODE,
          severity: :warning, tags: %i[CLEAN_CODE], applies_to: %i[ruby],
          fires: "  return value\n  log(value)\n",
          # A guard clause keeps the next line reachable, which is the shape a bare
          # \b(return|raise)\b read as unreachable across the whole tree.
          does_not_fire: "  return value if done?\n  log(value)\n",
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
        RuleDSL.rule :ABC_SIZE,
          severity: :warning, tags: %i[COMPLEXITY], applies_to: %i[ruby], autofix: false,
          description: "method ABC size over the ratchet threshold — extract until the pieces name themselves",
          example_path: "/repo/lib/example.rb",
          fires: "def dense(x)\n" + Array.new(20) { |i| "  v#{i} = x.call(#{i}) if x.ok?(#{i})\n" }.join + "end\n",
          does_not_fire: "def calm(x)\n  y = x.call\n  y ? y.to_s : nil\nend\n" do |src, path:|
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
