# frozen_string_literal: true

require "json"
require "psych"

module Master
  module Review
    module Scan
      module Rules
        class ConfigHierarchyRule < Rule
          MAX_DEPTH = 4
          TOP_LEVEL_LIMIT = 12

          def initialize
            super()
            @id = "CONFIG_HIERARCHY"
            @description = "config keys are grouped, non-duplicated, and shallow"
            @severity = :warning
            @rule_tags = %i[CONFIG HIERARCHY]
            @auto_fix = false
          end

          def check(code, path:)
            ext = File.extname(path).downcase
            return json_findings(code) if ext == ".json"
            return yaml_findings(code) if %w[.yml .yaml].include?(ext)

            []
          end

          private

          def yaml_findings(code)
            top = []
            findings = []
            code.each_line.with_index(1) do |line, line_number|
              next unless (match = line.match(/\A(\s*)([A-Za-z0-9_.-]+):/))

              top << match[2] if match[1].size.zero?
              depth = (match[1].size / 2) + 1
              findings << finding(line: line_number, message: "configuration nesting depth #{depth} exceeds #{MAX_DEPTH}") if depth > MAX_DEPTH
            end
            findings.concat(duplicate_key_findings(code))
            findings << finding(line: 1, message: "#{top.size} top-level configuration keys — group related settings") if top.uniq.size > TOP_LEVEL_LIMIT
            findings
          end

          # A duplicate key is the same key twice in the SAME mapping, which only
          # a parser can tell you.
          #
          # The old check keyed on "#{indent}:#{key}" across the whole file, so
          # every sibling record repeating a field name counted as a duplicate.
          # principle_map.yml scored 1074 findings for having 135 principles that
          # each declare meaning/detects/severity, and runtime.yml 1729. Across
          # the tree that was 8166 findings, all of them false: Psych finds
          # exactly zero real duplicate keys in data/**.yml. It was the single
          # largest category in MASTER's self-scan and none of it was true.
          #
          # An unparseable file gets no verdict rather than a guessed one -- the
          # depth and top-level-count checks above still run on the raw text.
          def duplicate_key_findings(code)
            document = Psych.parse(code)
            return [] unless document

            findings = []
            visit_mappings(document) do |node|
              counts = Hash.new { |hash, key| hash[key] = [] }
              node.children.each_slice(2) do |key, _value|
                next unless key.respond_to?(:value)

                counts[key.value] << key
              end
              counts.each_value do |nodes|
                next if nodes.size < 2

                findings << finding(line: nodes.last.start_line + 1,
                                    message: "duplicate configuration key #{nodes.first.value.inspect} in the same mapping")
              end
            end
            findings
          rescue Psych::SyntaxError => e
            # A file too broken to parse is not a file without duplicate keys.
            Master::Ground::Swallow.log(e, context: "duplicate_key_findings", severity: :load_bearing)
            []
          end

          def visit_mappings(node, &block)
            yield node if node.is_a?(Psych::Nodes::Mapping)
            node.children&.each { |child| visit_mappings(child, &block) }
          end

          def json_findings(code)
            data = JSON.parse(code)
            findings = []
            keys = data.is_a?(Hash) ? data.keys : []
            findings << finding(line: 1, message: "#{keys.size} top-level configuration keys — group related settings") if keys.size > TOP_LEVEL_LIMIT
            findings << finding(line: 1, message: "configuration nesting depth #{json_depth(data)} exceeds #{MAX_DEPTH}") if json_depth(data) > MAX_DEPTH
            findings
          rescue JSON::ParserError
            [finding(line: 1, message: "invalid JSON configuration — parse before trusting config hierarchy")]
          end

          def json_depth(value)
            case value
            when Hash then 1 + value.values.map { |child| json_depth(child) }.max.to_i
            when Array then 1 + value.map { |child| json_depth(child) }.max.to_i
            else 0
            end
          end
        end

        class CodeHierarchyRule < Rule
          TOP_LEVEL_LIMIT = 5

          def initialize
            super()
            @id = "CODE_HIERARCHY"
            @description = "related classes are grouped under clear namespaces"
            @severity = :warning
            @rule_tags = %i[ARCHITECTURE HIERARCHY]
            @auto_fix = false
          end

          def check(code, path:)
            return [] unless path.to_s.end_with?(".rb", ".rake")

            declarations = code.lines.each_with_index.filter_map do |line, index|
              match = line.match(/\A(class|module)\s+([A-Z][\w:]+)/)
              [index + 1, match[2]] if match
            end
            findings = []
            findings << finding(line: declarations.first[0], message: "#{declarations.size} top-level constants — group related classes into namespaces") if declarations.size > TOP_LEVEL_LIMIT
            shared_prefixes(declarations.map(&:last)).each do |prefix, names|
              findings << finding(line: 1, message: "#{names.size} #{prefix}* classes appear un-namespaced — create #{prefix} namespace")
            end
            findings
          end

          private

          def shared_prefixes(names)
            names.reject { |name| name.include?("::") }
                 .group_by { |name| name[/\A[A-Z][a-z]+/] }
                 .select { |prefix, grouped| prefix && grouped.size >= 3 }
          end
        end

        class LongParameterListRule < Rule
          LIMIT = 4

          def initialize
            super()
            @id = "LONG_PARAMETER_LIST"
            @description = "methods accept at most four parameters"
            @severity = :warning
            @rule_tags = %i[BLOATERS API]
            @auto_fix = false
          end

          def check(code, path:)
            return [] unless path.to_s.end_with?(".rb", ".rake")

            code.lines.each_with_index.filter_map do |line, index|
              match = line.match(/\bdef\s+[\w!?=]+\s*\(([^)]*)\)/)
              next unless match

              count = match[1].split(",").map(&:strip).reject(&:empty?).size
              finding(line: index + 1, message: "method has #{count} parameters (max #{LIMIT}) — introduce a value object or keywords") if count > LIMIT
            end
          end
        end

        class PrimitiveObsessionRule < Rule
          PRIMITIVE_HINTS = /\b(id|name|type|status|flag|count|price|amount|date|email|phone|url)\b|_id\z/i

          def initialize
            super()
            @id = "PRIMITIVE_OBSESSION"
            @description = "clusters of primitives should become small domain objects"
            @severity = :warning
            @rule_tags = %i[BLOATERS DOMAIN_MODELING]
            @auto_fix = false
          end

          def check(code, path:)
            return [] unless path.to_s.end_with?(".rb", ".rake")

            code.lines.each_with_index.filter_map do |line, index|
              next unless (match = line.match(/\bdef\s+[\w!?=]+\s*\(([^)]*)\)/))

              names = match[1].split(",").map { |part| part.split(/[:=]/).first.to_s.strip }
              primitive_names = names.grep(PRIMITIVE_HINTS)
              if primitive_names.size >= 4
                finding(line: index + 1, message: "primitive obsession: #{primitive_names.join(", ")} travel together — extract a domain object")
              end
            end
          end
        end

        # A bare `true` at a call site names nothing. `shadow_lift(path, true)`
        # is a riddle whose answer is in another file; `shadow_lift(path,
        # preserve_blacks: true)` is not. The positional boolean default is the
        # shape that produces it, and it is the shape the fix removes.
        #
        # Keyword parameters are exempt: `def render(path, cache: true)` already
        # forces the call site to say what is true, which is the whole point.
        class BooleanTrapRule < Rule
          def initialize
            super()
            @id = "BOOLEAN_TRAP"
            @description = "a positional boolean parameter makes every call site a riddle"
            @severity = :info
            @rule_tags = %i[API DOMAIN_LANGUAGE]
            @auto_fix = false
          end

          def check_ast(ast, _code, path:)
            return [] if ast.nil? || path.to_s.match?(%r{/(?:test|spec|fixtures)/})

            each_node(ast, Prism::DefNode).flat_map do |def_node|
              params = def_node.parameters
              next [] unless params

              Array(params.optionals).filter_map do |opt|
                literal = opt.value
                next unless literal.is_a?(Prism::TrueNode) || literal.is_a?(Prism::FalseNode)

                finding(line: def_node.location.start_line,
                  message: "#{def_node.name}(#{opt.name} = #{literal.is_a?(Prism::TrueNode)}) — the call site passes a bare boolean; make it `#{opt.name}:`")
              end
            end
          end
        end

        # DATA_CLUMPS, plural, because that spelling was already in the tree:
        # data/rules.yml carries a `violation_priors` row under it and
        # data/rules.yml rule_deps orders PRIMITIVE_OBSESSION `after: [DATA_CLUMPS]`.
        # Neither could do anything, because RuleOrder#topo_sort skips a
        # dependency whose id names no loaded rule and the prior is only read for
        # a rule that exists. Naming this one DATA_CLUMP, singular, would have
        # left both pointing at nothing for a second time.
        #
        # Two exclusions, both measured against this tree rather than guessed.
        # Identical signatures are one interface implemented many times —
        # check_ast(ast, code, path:) is a contract, and reporting its nine
        # implementers reports the interface working. Overlapping windows over
        # the same set of signatures are one clump seen through three frames, so
        # the longest run wins. Without either, the count was 81; with them, 48.
        class DataClumpsRule < Rule
          MIN_CLUMP = 3
          MIN_SIGNATURES = 3

          def initialize
            super()
            @id = "DATA_CLUMPS"
            @description = "the same parameters travelling together are a record struggling to be born"
            @severity = :info
            @rule_tags = %i[BLOATERS DOMAIN_MODELING]
            @auto_fix = false
          end

          def check_ast(ast, _code, path:)
            return [] if ast.nil? || path.to_s.match?(%r{/(?:test|spec|fixtures)/})

            signatures = each_node(ast, Prism::DefNode).filter_map do |def_node|
              # An underscored parameter is one the body does not use, so it
              # travels with the others by accident rather than by meaning.
              names = parameter_names(def_node).reject { |name| name.start_with?("_") }
              [def_node, names] if names.size >= MIN_CLUMP
            end
            return [] if signatures.size < MIN_SIGNATURES

            longest_runs(runs_by_window(signatures)).filter_map do |run, pairs|
              next if pairs.size < MIN_SIGNATURES || pairs.map(&:last).uniq.size == 1

              finding(line: pairs.map { |def_node, _names| def_node.location.start_line }.min,
                message: "#{run.join(", ")} travel together through #{pairs.size} signatures — give them one object")
            end
          end

          private

          def runs_by_window(signatures)
            runs = Hash.new { |hash, key| hash[key] = [] }
            signatures.each do |def_node, names|
              names.each_cons(MIN_CLUMP) { |run| runs[run] << [def_node, names] }
            end
            runs
          end

          def longest_runs(runs)
            runs.group_by { |_run, pairs| pairs.map { |def_node, _names| def_node.location.start_line }.sort }
                .values.map { |group| group.max_by { |run, _pairs| run.size } }.to_h
          end
        end

        class CouplerRule < Rule
          MESSAGE_CHAIN = /\b\w+(?:\.\w+){4,}/
          INTIMACY = /\.(?:instance_variable_get|instance_variable_set|send|public_send)\s*\(/

          def initialize
            super()
            @id = "COUPLER_SMELLS"
            @description = "inappropriate intimacy and message chains"
            @severity = :warning
            @rule_tags = %i[COUPLING DEMETER]
            @auto_fix = false
          end

          def check(code, path:)
            return [] unless path.to_s.end_with?(".rb", ".rake")

            findings = []
            code.lines.each_with_index do |line, index|
              findings << finding(line: index + 1, message: "message chain #{line[MESSAGE_CHAIN].strip} — introduce a query method") if line.match?(MESSAGE_CHAIN)
              findings << finding(line: index + 1, message: "inappropriate intimacy via reflective access — expose a real collaboration boundary") if line.match?(INTIMACY)
            end
            findings
          end
        end

        # Split from CouplerRule 2026-07-12: rules.yml's rule_deps SRP entry already
        # referenced FEATURE_ENVY as its own id (SRP: after: [FEATURE_ENVY,
        # god_class]) — a dangling reference, since the check previously lived
        # under COUPLER_SMELLS. This gives it a real matching id and a single
        # responsibility of its own.
        class FeatureEnvyRule < Rule
          def initialize
            super()
            @id = "FEATURE_ENVY"
            @description = "method talks to one collaborator's internals more than its own"
            @severity = :warning
            @rule_tags = %i[COUPLING DEMETER]
            @auto_fix = false
          end

          def check(code, path:)
            return [] unless path.to_s.end_with?(".rb", ".rake")

            methods(code).filter_map do |start_line, body|
              receivers = body.scan(/\b([a-z][a-zA-Z0-9_]*)\./).flatten
              next if receivers.size < 5

              dominant, count = receivers.tally.max_by { |_receiver, total| total }
              local = body.scan(/(?:@|\bself\.)/).size
              if dominant && count >= 4 && count > local
                finding(line: start_line, message: "feature envy: method talks to #{dominant} #{count} times — move behavior closer to that object")
              end
            end
          end

          private

          def methods(code)
            result = []
            current = nil
            code.each_line.with_index(1) do |line, index|
              current = [index, +""] if line.match?(/\A\s*def\b/)
              current[1] << line if current
              if current && line.match?(/\A\s*end\b/)
                result << current
                current = nil
              end
            end
            result
          end
        end

        class LazyClassRule < Rule
          def initialize
            super()
            @id = "LAZY_CLASS"
            @description = "classes should own behavior, not only delegate"
            @severity = :warning
            @rule_tags = %i[DISPENSABLES SRP]
            @auto_fix = false
          end

          def check(code, path:)
            return [] unless path.to_s.end_with?(".rb", ".rake")

            classes(code).filter_map do |line, body|
              defs = body.scan(/^\s*def\s+/).size
              delegates = body.scan(/^\s*(?:delegate\b|def\s+\w+[!?=]?\s*;?\s*@?\w+\.\w+)/).size
              if defs.positive? && delegates >= defs && body.lines.size < 50
                finding(line:, message: "lazy class only delegates — inline it or give it a real responsibility")
              end
            end
          end

          private

          def classes(code)
            result = []
            current = nil
            code.each_line.with_index(1) do |line, index|
              current = [index, +""] if line.match?(/\A\s*class\b/)
              current[1] << line if current
              if current && line.match?(/\A\s*end\b/)
                result << current
                current = nil
              end
            end
            result
          end
        end
      end
    end
  end
end
