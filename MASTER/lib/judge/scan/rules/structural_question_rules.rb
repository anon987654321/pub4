# frozen_string_literal: true

require "json"
require "set"

module Master
  module Judge
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
            seen = Set.new
            top = []
            findings = []
            code.each_line.with_index(1) do |line, line_number|
              next unless (match = line.match(/\A(\s*)([A-Za-z0-9_.-]+):/))

              indent = match[1].size
              key = match[2]
              top << key if indent.zero?
              depth = (indent / 2) + 1
              marker = "#{indent}:#{key}"
              findings << finding(line: line_number, message: "duplicate configuration key #{key.inspect} at indent #{indent}") if seen.include?(marker)
              findings << finding(line: line_number, message: "configuration nesting depth #{depth} exceeds #{MAX_DEPTH}") if depth > MAX_DEPTH
              seen << marker
            end
            findings << finding(line: 1, message: "#{top.size} top-level configuration keys — group related settings") if top.uniq.size > TOP_LEVEL_LIMIT
            findings
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

        # Split from CouplerRule 2026-07-12: rule_deps.yml's SRP entry already
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
                finding(line: line, message: "lazy class only delegates — inline it or give it a real responsibility")
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
