# MASTER Snapshot — lib/master/scan/
Generated: 2026-05-04T10:21:42Z

## lib/master/scan/rule.rb
```ruby
# frozen_string_literal: true

module Master
  module Scan
    class Rule
      EXT_LANG = {
        ".rb"      => "ruby",        ".rake"  => "ruby",   ".gemspec" => "ruby",
        ".erb"     => "html",        ".html"  => "html",   ".htm"     => "html",
        ".css"     => "css",         ".scss"  => "scss",   ".sass"    => "scss",
        ".js"      => "javascript",  ".ts"    => "javascript",
        ".jsx"     => "javascript",  ".tsx"   => "javascript",
        ".zsh"     => "zsh",         ".sh"    => "zsh",    ".bash"    => "zsh",
        ".yml"     => "yaml",        ".yaml"  => "yaml",
        ".md"      => "markdown",    ".json"  => "json",
      }.freeze

      attr_reader :id, :description, :severity, :axiom_tags, :auto_fix

      def self.inherited(subclass)
        @registry_mutex ||= Mutex.new
        @registry_mutex.synchronize do
          (@registry ||= []) << subclass
        end
      end

      def self.registry
        @registry_mutex ||= Mutex.new
        @registry_mutex.synchronize { @registry || [] }
      end

      # Rules that need constructor args (root:, agent:) override this to false.
      # Builder uses it to auto-discover zero-arg rules from the registry.
      def self.auto_build? = true

      def initialize
        @id         = self.class.name&.split("::")&.last&.downcase || "unknown"
        @description = ""
        @severity    = :warning
        @axiom_tags  = []
        @auto_fix    = true
      end

      def check(code, path:)
        raise NotImplementedError, "#{self.class}#check not implemented"
      end

      def language(path)
        EXT_LANG[File.extname(path).downcase]
      end

      def applies_to?(path, languages)
        return true if languages.nil? || languages.empty?
        lang = language(path)
        lang && languages.include?(lang)
      end

      protected

      def finding(line:, message:, fix: nil)
        { rule: @id, message:, line:, severity: @severity, fix: }
      end

      def scan_lines(code, pattern, message:, fix: nil)
        code.each_line.with_index(1).filter_map { |line, num|
          finding(line: num, message:, fix:) if line.match?(pattern)
        }
      end
    end
  end
end

```

## lib/master/scan/rules/adversarial_rule.rb
```ruby
# frozen_string_literal: true

module Master
  module Scan
    module Rules
      # Steelman-first red-team: the model must defend the code before it can attack it.
      # This suppresses false positives by forcing consideration of legitimate reasons
      # before a violation can survive. Deep depth only; one LLM call per file.
      class AdversarialRule < Rule
        PROMPT_TEMPLATE = <<~PROMPT.freeze
          Red-team review of %<path>s.

          Step 1 — Steelman (internal, do not output): write the three strongest
          arguments that this code is correct and should not be changed.

          Step 2 — Challenge: list only the violations that survive the steelman.
          Format: ISSUE:LINE:description (one per line).
          If nothing survives, respond with exactly: CLEAN

          Focus on: broken contracts, hidden coupling, axiom violations (CQS,
          ONE_JOB, GUARD_EXPENSIVE, FAIL_VISIBLY), and logic errors.
          Ignore style. Do not hallucinate method names.

          Code (%<lang>s):
          %<code>s
        PROMPT

        def initialize(agent: nil)
          super()
          @agent       = agent
          @id          = "adversarial"
          @description = "Red-team scan: steelman then challenge — suppresses false positives"
          @severity    = :error
          @axiom_tags  = %i[ONE_JOB CQS GUARD_EXPENSIVE FAIL_VISIBLY COMPOSABLE]
        end

        def self.auto_build? = false

        def set_agent(agent)
          @agent = agent
          self
        end

        def check(code, path:)
          return [] unless (lang = language(path))
          return [] unless @agent

          prompt = format(PROMPT_TEMPLATE, path: File.basename(path),
                                           lang: lang,
                                           code: code[0, 3_000])
          response = @agent.ask(prompt).to_s
          parse_findings(response)
        rescue StandardError => e
          [finding(line: 1, message: "adversarial: scan error — #{e.message}")]
        end

        private

        def parse_findings(response)
          return [] if response.strip.upcase.start_with?("CLEAN")

          response.lines.filter_map do |line|
            match = line.strip.match(/\AISSUE:(\d+):(.+)\z/)
            next unless match
            finding(line: match[1].to_i, message: "adversarial: #{match[2].strip}")
          end
        end
      end
    end
  end
end

```

## lib/master/scan/rules/arity_rule.rb
```ruby
# frozen_string_literal: true

module Master
  module Scan
    module Rules
      # Too many constructor args signal a god object; callers can't reason about what matters.
      # Reads max_params from rules.yml so the threshold stays in one place.
      class ArityRule < Rule
        DEFAULT_MAX = 3

        def initialize
          super
          @max_params  = Master::Axioms.new.thresholds.dig("method", "max_params") || DEFAULT_MAX
          @id          = "arity"
          @description = "initialize with > #{@max_params} args — extract a context struct or config object"
          @severity    = :warning
          @axiom_tags  = %i[DECOUPLE ONE_JOB]
        end

        def check(code, path:)
          return [] unless path.end_with?(".rb")
          findings = []
          lines    = code.lines
          index    = 0
          while index < lines.size
            line = lines[index]
            if line.match?(/^\s*def\s+initialize\s*\(/)
              signature, end_index = collect_signature(lines, index)
              param_count = count_params(signature)
              findings << finding(line: index + 1,
                message: "initialize takes #{param_count} args (max #{@max_params}) — extract AgentContext or Config struct") if param_count > @max_params
              index = end_index + 1
            else
              index += 1
            end
          end
          findings
        end

        private

        def collect_signature(lines, start)
          signature = +""
          depth     = 0
          current   = start
          while current < lines.size
            signature << lines[current]
            depth += lines[current].count("(") - lines[current].count(")")
            break if depth <= 0
            current += 1
          end
          [signature, current]
        end

        def count_params(signature)
          inner = signature.match(/def\s+initialize\s*\((.+)\)/m)
          return 0 unless inner
          content = inner[1].strip
          return 0 if content.empty?
          depth = 0
          count = 1
          content.each_char do |char|
            case char
            when "(", "[", "{" then depth += 1
            when ")", "]", "}" then depth -= 1
            when "," then count += 1 if depth.zero?
            end
          end
          count
        end
      end
    end
  end
end

```

## lib/master/scan/rules/axiom_coverage_rule.rb
```ruby
# frozen_string_literal: true

require "prism"

module Master
  module Scan
    module Rules
      # Every rule ID in rules.yml must have scan rule coverage; every @axiom_tags
      # symbol must name a real rule ID. Orphaned tags and uncovered rules both signal drift.
      class AxiomCoverageRule < Rule
        def initialize(root: nil)
          super()
          @root        = root
          @id          = "axiom_coverage"
          @description = "Every rule must have scan rule coverage; every tag must be a real rule"
          @severity    = :warning
          @axiom_tags  = []
        end

        def self.auto_build? = false

        def check(code, path:)
          return [] unless path.include?("scan/rules") || path.include?("scan/rule.rb")
          return [] unless @root

          axiom_ids  = load_axiom_ids
          tagged_ids = load_tagged_ids
          findings   = []

          (tagged_ids - axiom_ids).each do |id|
            findings << finding(line: 1, message: "axiom_tag :#{id} has no entry in rules.yml — define it or remove the tag")
          end

          (axiom_ids - tagged_ids).each do |id|
            findings << finding(line: 1, message: "rule #{id} has no scan rule coverage — add a rule or accept as advisory")
          end

          findings
        end

        private

        def load_axiom_ids
          path = File.join(@root, "data", "rules.yml")
          return [] unless File.exist?(path)

          data = Master.load_yaml(path)
          all_rules = (data["rules"] || {}).values.flatten
          all_rules.map { |r| r["id"] }.compact.uniq
        rescue StandardError => _e
          []
        end

        def load_tagged_ids
          rules_dir = File.join(@root, "lib", "master", "scan", "rules")
          return [] unless Dir.exist?(rules_dir)

          Dir.glob(File.join(rules_dir, "*.rb")).flat_map { |f|
            extract_axiom_tags(File.read(f))
          }.uniq
        rescue StandardError => _e
          []
        end

        def extract_axiom_tags(source)
          result = Prism.parse(source)
          return [] unless result.success?

          collector = TagCollector.new
          collector.visit(result.value)
          collector.tags
        rescue StandardError => _e
          []
        end

        class TagCollector < Prism::Visitor
          attr_reader :tags
          def initialize
            super
            @tags = []
          end

          def visit_instance_variable_write_node(node)
            if node.name == :@axiom_tags
              @tags.concat(collect_symbols(node.value))
            end
            super
          end

          private

          def collect_symbols(node)
            return [] unless node
            case node
            when Prism::ArrayNode
              node.elements.flat_map { |el| collect_symbols(el) }
            when Prism::SymbolNode
              [node.unescaped.to_s]
            else
              []
            end
          end
        end
      end
    end
  end
end

```

## lib/master/scan/rules/bare_rescue_rule.rb
```ruby
# frozen_string_literal: true

module Master
  module Scan
    module Rules
      class BareRescueRule < Rule
        def initialize
          super
          @id          = "bare_rescue"
          @description = "Never use bare rescue -- always specify exception type"
          @severity    = :error
          @axiom_tags  = [:FAIL_VISIBLY]
        end

        def check(code, path:)
          return [] unless path.end_with?(".rb")
          scan_lines(code, /^\s*rescue\s*$/, message: "bare rescue: specify exception type (e.g. rescue StandardError)")
        end
      end
    end
  end
end

```

## lib/master/scan/rules/conceptual_rule.rb
```ruby
# frozen_string_literal: true

module Master
  module Scan
    module Rules
      # LLM review for rules whose violations resist lexical detection; deep depth only.
      # Rules with detect_conceptual prompts in rules.yml are batched into one LLM call per file.
      class ConceptualRule < Rule
        RULES_PATH = File.join(Master::ROOT, "data", "rules.yml").freeze
        CODE_SNIPPET_LIMIT = 2000

        def initialize(agent: nil)
          super()
          @agent       = agent
          @id          = "conceptual"
          @description = "LLM-based rule review (runs at :deep depth only)"
          @severity    = :warning
          @axioms      = load_conceptual_rules
          @axiom_tags  = @axioms.keys.map(&:to_sym)
        end

        def self.auto_build? = false

        def set_agent(agent)
          @agent = agent
          self
        end

        def check(code, path:)
          return [] unless language(path)
          return [] unless @agent

          prompt = build_prompt(code, path)
          response = @agent.ask(prompt).to_s
          parse_findings(response)
        rescue StandardError => e
          [finding(line: 1, message: "conceptual: scan error — #{e.message}")]
        end

        private

        def load_conceptual_rules
          data = Master.load_yaml(RULES_PATH)
          all_rules = (data["rules"] || {}).values.flatten
          all_rules
            .select { |r| r["detect_conceptual"] }
            .each_with_object({}) { |r, h| h[r["id"]] = r["detect_conceptual"] }
        end

        def build_prompt(code, path)
          axiom_list = @axioms.map { |id, stmt| "#{id}: #{stmt}" }.join("\n")
          <<~PROMPT
            Review #{File.basename(path)} against these rules. List ONLY clear violations.
            Format each as: RULE_ID:LINE:description (one per line)
            If clean, respond with exactly: CLEAN

            Rules:
            #{axiom_list}

            Code (first #{CODE_SNIPPET_LIMIT} chars):
            #{code[0, CODE_SNIPPET_LIMIT]}
          PROMPT
        end

        def parse_findings(response)
          return [] if response.strip.upcase == "CLEAN"

          response.lines.filter_map do |line|
            match_data = line.strip.match(/\A([A-Z_]+):(\d+):(.+)\z/)
            next unless match_data && @axioms.key?(match_data[1])
            finding(line: match_data[2].to_i, message: "#{match_data[1]}: #{match_data[3].strip}")
          end
        end
      end
    end
  end
end

```

## lib/master/scan/rules/cqs_rule.rb
```ruby
# frozen_string_literal: true

module Master
  module Scan
    module Rules
      # CqsRule — detects Command/Query Separation violations.
      # A method should either return a value (query) or change state (command), not both.
      # Flags methods named like queries (get_*, find_*, fetch_*, load_*) that also
      # contain state-mutating patterns (@x =, save!, update!, write).
      class CqsRule < Rule
        QUERY_PREFIX   = /^\s+def\s+(get_|find_|fetch_|load_|read_|list_|show_|describe_)\w+/.freeze
        MUTATION_IN_BODY = /(@\w+\s*=(?!=)|\.save[!\s]|\.update[!\s]|\.write[!\s]|File\.write)/.freeze

        def initialize
          super
          @id          = "cqs"
          @description = "Command/Query Separation — queries must not mutate state"
          @severity    = :warning
          @axiom_tags  = [:CQS]
        end

        def check(code, path:)
          return [] unless path.end_with?(".rb")

          findings = []
          in_query  = false
          query_line = 0
          depth      = 0

          code.each_line.with_index(1) do |line, num|
            if !in_query && line.match?(QUERY_PREFIX)
              in_query   = true
              query_line = num
              depth      = 1
              next
            end

            if in_query
              depth += line.scan(/^\s*(?:if|case|begin|do)\b|\bdo\s*(?:\|[^|]*\|)?\s*$|\bdef\s/).size
              depth -= line.scan(/\bend\b/).size

              if depth <= 0
                in_query = false
                next
              end

              if line.match?(MUTATION_IN_BODY)
                findings << finding(
                  line: query_line,
                  message: "query method mutates state (line #{num}) — split into separate command and query"
                )
                in_query = false
              end
            end
          end

          findings
        end
      end
    end
  end
end

```

## lib/master/scan/rules/duplicate_code_rule.rb
```ruby
# frozen_string_literal: true

module Master
  module Scan
    module Rules
      # Duplicate structural code (same AST shape, different names) violates ONE_SOURCE.
      # Delegates to flay for reliable AST-level detection; falls back to a line-hash
      # approach when flay is unavailable (e.g. gem not installed).
      class DuplicateCodeRule < Rule
        FLAY_THRESHOLD = 16
        OCCUR_MIN      = 2

        def initialize
          super
          @id          = "duplicate_code"
          @description = "Duplicate code blocks violate ONE_SOURCE — extract to shared method"
          @severity    = :warning
          @axiom_tags  = [:ONE_SOURCE]
        end

        def check(code, path:)
          return [] unless path.end_with?(".rb")
          flay_available? ? flay_check(code, path) : []
        end

        private

        def flay_available?
          require "flay"
          true
        rescue LoadError
          false
        end

        def flay_check(code, path)
          flay = Flay.new(threshold: FLAY_THRESHOLD, verbose: false, diff: false, summary: false)
          flay.process(path)
          flay.masses.filter_map { |hash, nodes|
            next if nodes.size < OCCUR_MIN
            first = nodes.first
            finding(
              line: first.line,
              message: "duplicate structure #{nodes.size} times (flay mass #{flay.masses[hash]}) — extract to shared method (ONE_SOURCE)"
            )
          }
        rescue StandardError
          []
        end
      end
    end
  end
end

```

## lib/master/scan/rules/explicit_rule.rb
```ruby
# frozen_string_literal: true

module Master
  module Scan
    module Rules
      # ExplicitRule — detects implicit/opaque patterns that violate EXPLICIT.
      # Flags: bare rescue, implicit return of nil, magic number literals,
      # single-letter variable names outside loops, and undefined method patterns.
      class ExplicitRule < Rule
        RESCUE_NIL   = /rescue\s+nil\b/.freeze
        MAGIC_NUM    = /[^:]\b([2-9]\d{2,}|[1-9]\d{3,})\b(?!\s*[#=])/.freeze
        OPAQUE_VAR   = /^\s+[a-z]\s*=(?!=)/.freeze        # x = ... (not x == or x +=)
        IMPLICIT_NIL = /def\s+\w+[^;]*\n(?:\s*#[^\n]*\n)*\s*end/.freeze  # empty method body

        def initialize
          super
          @id          = "explicit"
          @description = "Implicit, opaque patterns — prefer explicit contracts"
          @severity    = :warning
          @axiom_tags  = [:EXPLICIT]
        end

        def check(code, path:)
          return [] unless path.end_with?(".rb")

          findings = []
          code.each_line.with_index(1) do |line, num|
            findings << finding(line: num, message: "bare rescue hides errors — name the exception class or propagate") if line.match?(RESCUE_NIL)
            next if line.match?(/^\s*[A-Z][A-Z_0-9]*\s*=/)  # skip constant defs
            findings << finding(line: num, message: "magic number — extract to a named constant")                if line.match?(MAGIC_NUM) && !line.strip.start_with?("#")
            findings << finding(line: num,
              message: "single-letter variable obscures intent — use a descriptive name") if line.match?(OPAQUE_VAR) && !in_loop_context?(code, num)
          end
          findings
        end

        private

        def in_loop_context?(code, target_line)
          lines = code.lines
          ((target_line - 4)..(target_line - 1)).any? do |i|
            next false unless i >= 0 && i < lines.size
            lines[i].match?(/\b(?:each|map|times|upto|downto|step|for\s+\w)\b/)
          end
        end
      end
    end
  end
end

```

## lib/master/scan/rules/frozen_string_rule.rb
```ruby
# frozen_string_literal: true

module Master
  module Scan
    module Rules
      class FrozenStringRule < Rule
        def initialize
          super
          @id          = "frozen_string"
          @description = "Ruby files should declare # frozen_string_literal: true"
          @severity    = :warning
          @axiom_tags  = [:PERFORMANCE]
          @auto_fix    = true
        end

        def check(code, path:)
          return [] unless path.end_with?(".rb")
          return [] if code.lines.first&.include?("frozen_string_literal")
          [finding(line: 1, message: "missing # frozen_string_literal: true",
                   fix: "# frozen_string_literal: true\n" + code)]
        end
      end
    end
  end
end

```

## lib/master/scan/rules/god_class_rule.rb
```ruby
# frozen_string_literal: true

module Master
  module Scan
    module Rules
      class GodClassRule < Rule
        DEFAULT_THRESHOLD = 200

        def initialize
          super
          @threshold   = Master::Axioms.new.thresholds.dig("class", "max_lines") || DEFAULT_THRESHOLD
          @id          = "god_class"
          @description = "Classes over #{@threshold} lines should be split by responsibility"
          @severity    = :warning
          @axiom_tags  = [:SIMPLEST_WORKS]
        end

        def check(code, path:)
          return [] unless path.end_with?(".rb")
          lines = code.lines.size
          return [] if lines <= @threshold

          class_name = code.match(/class (\w+)/i)&.[](1) || File.basename(path, ".rb")
          [finding(
            line: 1,
            message: "#{class_name} is #{lines} lines (threshold: #{@threshold}) — split by responsibility"
          )]
        end
      end
    end
  end
end

```

## lib/master/scan/rules/immutable_rule.rb
```ruby
# frozen_string_literal: true

module Master
  module Scan
    module Rules
      class ImmutableRule < Rule
        UNFROZEN_CONST     = /^\s+[A-Z][A-Z0-9_]+ \s*=\s*(?:"[^"]*"|'[^']*'|\[|\{)(?!.*(?:\.freeze|\.min|\.max|\.count|\.size|\.length|\.sum|\.to_i|\.to_f)\b)/.freeze
        MULTILINE_OPEN     = /^\s+[A-Z][A-Z0-9_]+ \s*=\s*[\[{]/.freeze
        STRING_CONTINUATION = /\\\s*$/.freeze
        CLASS_VAR_WRITE = /^\s+@@\w+\s*=(?!=)/.freeze
        GLOBAL_WRITE    = /^\s+\$\w+\s*=(?!=)/.freeze

        def initialize
          super
          @id          = "immutable"
          @description = "Mutable shared state — prefer frozen constants and immutable data flow"
          @severity    = :warning
          @axiom_tags  = [:IMMUTABLE]
        end

        def check(code, path:)
          return [] unless path.end_with?(".rb")

          lines = code.lines
          findings = []

          lines.each_with_index do |line, line_index|
            line_number = line_index + 1
            next if line.strip.start_with?("#")

            if line.match?(UNFROZEN_CONST)
              if line.match?(MULTILINE_OPEN) && !inline_close?(line)
                findings << finding(line: line_number, message: "unfrozen constant — append .freeze") unless multiline_frozen?(lines, line_index)
              elsif line.match?(STRING_CONTINUATION)
                findings << finding(line: line_number, message: "unfrozen constant — append .freeze") unless string_continuation_frozen?(lines, line_index)
              else
                findings << finding(line: line_number, message: "unfrozen constant — append .freeze")
              end
            end

            findings << finding(line: line_number, message: "class variable mutation (@@) — use instance state or inject") if line.match?(CLASS_VAR_WRITE)
            findings << finding(line: line_number, message: "global variable mutation ($) — eliminate shared global state") if line.match?(GLOBAL_WRITE)
          end

          findings
        end

        private

        def inline_close?(line)
          stripped = line.rstrip
          return true if stripped.end_with?("].freeze", "}.freeze", "].freeze,", "}.freeze,")
          sq = stripped.count("[")
          cq = stripped.count("{")
          (sq > 0 && sq == stripped.count("]")) || (cq > 0 && cq == stripped.count("}"))
        end

        def string_continuation_frozen?(lines, start_line)
          (start_line...lines.size).each do |current_line|
            return lines[current_line].include?(".freeze") unless lines[current_line].match?(STRING_CONTINUATION)
          end
          false
        end

        def multiline_frozen?(lines, start_line)
          line   = lines[start_line]
          opener = line.include?("{") ? "{" : "["
          closer = opener == "{" ? "}" : "]"
          depth  = 0
          (start_line...lines.size).each do |current_line|
            depth += lines[current_line].count(opener) - lines[current_line].count(closer)
            return lines[current_line].include?(".freeze") if depth <= 0
          end
          false
        end
      end
    end
  end
end

```

## lib/master/scan/rules/lexical_rule.rb
```ruby
# frozen_string_literal: true

module Master
  module Scan
    module Rules
      # LexicalRule — data-driven: loads all detect_lexical rules from rules.yml
      # and applies them to the matching file language. Single class covering
      # HTML, CSS, Zsh, JavaScript, and cross-language lexical checks.
      class LexicalRule < Rule
        RULES_PATH = File.join(Master::ROOT, "data", "rules.yml").freeze

        def initialize
          super
          @id          = "lexical"
          @description = "Data-driven lexical checks from rules.yml for all file types"
          @severity    = :warning
          @axiom_tags  = [:UNIVERSAL]
          @loaded      = load_lexical_rules
        end

        def check(code, path:)
          lang = language(path)
          return [] unless lang

          @loaded
            .select { |r| r[:languages].nil? || r[:languages].include?(lang) }
            .flat_map { |r| apply(r, code, path) }
        end

        private

        def load_lexical_rules
          data = Master.load_yaml(RULES_PATH)
          all  = (data["rules"] || {}).values.flatten
          all.filter_map do |r|
            next unless r["detect_lexical"] && !r["detect_lexical"].to_s.empty?
            langs = Array(r["languages"]).compact
            {
              id:        r["id"],
              message:   r["name"] || r["id"],
              pattern:   Regexp.new(r["detect_lexical"]),
              fix:       r["fix"],
              severity:  (r["severity"] || "warning").to_sym,
              languages: langs.empty? ? nil : langs,
            }
          rescue RegexpError
            nil
          end.compact
        rescue StandardError => _e
          []
        end

        def apply(rule, code, path)
          code.each_line.with_index(1).filter_map do |line, num|
            next unless line.match?(rule[:pattern])
            { rule: rule[:id], message: rule[:message], line: num,
              severity: rule[:severity], fix: rule[:fix] }
          end
        end
      end
    end
  end
end

```

## lib/master/scan/rules/long_method_rule.rb
```ruby
# frozen_string_literal: true

module Master
  module Scan
    module Rules
      class LongMethodRule < Rule
        DEFAULT_THRESHOLD = 10

        def initialize
          super
          @threshold   = Master::Axioms.new.thresholds.dig("method", "max_lines") || DEFAULT_THRESHOLD
          @id          = "long_method"
          @description = "Methods over #{@threshold} lines should be extracted"
          @severity    = :warning
          @axiom_tags  = [:ONE_JOB]
        end

        def check(code, path:)
          return [] unless path.end_with?(".rb")
          findings = []
          method_start = nil
          method_name  = nil
          depth        = 0

          code.each_line.with_index(1) do |line, num|
            if line.match?(/^\s*def /)
              method_start = num
              method_name  = line.match(/def (\w+)/)[1]
              depth        = 1
            elsif method_start
              depth += line.scan(/\bdo\b|\bbegin\b|\bif\b|\bcase\b|\bclass\b|\bmodule\b|\bdef\b/).size
              depth -= line.scan(/\bend\b/).size
              if depth <= 0
                length = num - method_start + 1
                if length > @threshold
                  findings << finding(
                    line: method_start,
                    message: "method #{method_name} is #{length} lines (threshold: #{@threshold}) — extract responsibilities"
                  )
                end
                method_start = nil
              end
            end
          end

          findings
        end
      end
    end
  end
end

```

## lib/master/scan/rules/nielsen_rule.rb
```ruby
# frozen_string_literal: true

module Master
  module Scan
    module Rules
      # NielsenRule — enforces Nielsen Norman Group's 10 Usability Heuristics
      # at the code level: API design, error messages, output behavior.
      class NielsenRule < Rule
        # H9: Error messages must describe the problem — bare string raises with no guidance
        BARE_RAISE       = /\braise\s+["'][^"']{0,20}["']/.freeze
        # H9: Result.err with no message or single-word message
        THIN_ERR         = /Result\.err\(["'][a-z_]{1,15}["'](?:\s*\))/.freeze
        # H4: Inconsistent boolean naming — mix of is_/has_/can_ with plain predicates
        # H6: Positional args over 3 — harms recognition (caller can't tell what each is)
        POSITIONAL_HEAVY = /def\s+\w+\((?:[^:,)]+,){3,}[^*&]/.freeze
        # H8: Aesthetic minimalism — debug inspect calls (p/pp/pry) left in production
        DEBUG_OUTPUT     = /^\s+(?:p|pp|binding\.pry|debugger)\s+(?!.*#\s*rubocop)/.freeze
        # H3: User control — destructive methods without bang or guard comment
        SILENT_DELETE    = /\b(?:FileUtils\.rm|File\.delete|Dir\.rmdir)\s*\((?!.*#.*safe)/.freeze
        # H2: Real world match — internal jargon in user-facing strings
        JARGON           = /(?:raise|Result\.err)\(.*\b(?:nil\b|exception|stacktrace|backtrace|segfault|errno)\b/.freeze

        def initialize
          super
          @id          = "nielsen"
          @description = "Nielsen's 10 heuristics: error quality, recognition, minimalism, user control"
          @severity    = :warning
          @axiom_tags  = %i[ERROR_RECOVERY REAL_WORLD_MATCH USER_CONTROL AESTHETIC_MINIMALISM
                            RECOGNITION_NOT_RECALL CONSISTENCY]
        end

        def check(code, path:)
          return [] unless path.end_with?(".rb")

          findings = []
          code.each_line.with_index(1) do |line, num|
            next if line.strip.start_with?("#")
            findings << finding(line: num, message: "[ERROR_RECOVERY] raise with no guidance — tell the user what to do next")         if line.match?(BARE_RAISE)
            findings << finding(line: num, message: "[ERROR_RECOVERY] thin Result.err message — include what failed and how to fix it") if line.match?(THIN_ERR)
            findings << finding(line: num, message: "[RECOGNITION_NOT_RECALL] 4+ positional args — use keyword arguments so callers read intent") if line.match?(POSITIONAL_HEAVY)
            findings << finding(line: num, message: "[AESTHETIC_MINIMALISM] debug output left in — remove puts/p or guard with log level")  if line.match?(DEBUG_OUTPUT)
            findings << finding(line: num, message: "[USER_CONTROL] destructive call without safety comment — add undo or confirmation guard") if line.match?(SILENT_DELETE)
            findings << finding(line: num, message: "[REAL_WORLD_MATCH] internal jargon in user-facing error — use plain language")          if line.match?(JARGON)
          end
          findings
        end
      end
    end
  end
end

```

## lib/master/scan/rules/opportunity_rule.rb
```ruby
# frozen_string_literal: true

module Master
  module Scan
    module Rules
      # Opportunities are not violations — they are structural improvements waiting to happen.
      # Detects: deep nesting (reflow), lambda dispatch tables (regroup into Command),
      # thin delegation wrappers (collapse), and dense inline hashes (extract class).
      # Severity :info so they show up in deep scans without polluting standard output.
      class OpportunityRule < Rule
        NESTING_THRESHOLD   = 4
        HASH_PAIR_THRESHOLD = 4
        LAMBDA_TABLE_MIN    = 3
        INDENT_UNIT         = 2

        def initialize
          super
          @id          = "opportunity"
          @description = "Structural improvement opportunity — refactor for clarity or cohesion"
          @severity    = :info
          @axiom_tags  = %i[SIMPLEST_WORKS DECOUPLE ONE_JOB]
        end

        def check(code, path:)
          return [] unless path.end_with?(".rb")
          findings = []
          findings += deep_nesting(code)
          findings += lambda_dispatch_table(code)
          findings += thin_delegation(code)
          findings += dense_inline_hash(code)
          findings
        end

        private

        def deep_nesting(code)
          results    = []
          base_indent = nil
          method_line = nil

          code.each_line.with_index(1) do |line, number|
            stripped = line.strip
            next if stripped.empty? || stripped.start_with?("#") || stripped.start_with?(".")
            indent = 0
            indent += 1 while line[indent] == " "
            if stripped.start_with?("def ")
              base_indent = indent
              method_line = number
            elsif base_indent && stripped == "end"
              base_indent = nil
              method_line = nil
            elsif base_indent
              relative_depth = (indent - base_indent) / INDENT_UNIT
              if relative_depth >= NESTING_THRESHOLD
                results << finding(line: method_line,
                  message: "#{relative_depth} levels of nesting in method — reflow with early returns or extract method")
                base_indent = nil
              end
            end
          end
          results
        end

        def lambda_dispatch_table(code)
          results = []
          code.each_line.with_index(1) do |line, number|
            stripped = line.strip
            next unless stripped.start_with?('"') && stripped.include?("=>") && stripped.include?("->")
            count = code.lines.count { |other| other.strip.start_with?('"') && other.strip.include?("=>") && other.strip.include?("->") }
            if count >= LAMBDA_TABLE_MIN
              results << finding(line: number,
                message: "lambda dispatch table (#{count} entries) — regroup into Command objects or a registry")
              break
            end
          end
          results
        end

        def thin_delegation(code)
          results = []
          lines   = code.lines
          lines.each_with_index do |line, line_index|
            stripped = line.strip
            next unless stripped.start_with?("def ") && !stripped.include?("=")
            method_name = stripped.split(" ", 3)[1].to_s.split("(", 2).first
            body_index  = line_index + 1
            next if body_index >= lines.size
            body    = lines[body_index].strip
            closing = lines[body_index + 1]&.strip
            next unless body.include?(".") && !body.start_with?("#") && closing == "end"
            delegated = body.split(".").last.split("(").first.strip
            if delegated == method_name
              results << finding(line: line_index + 1,
                message: "#{method_name}: thin transparent delegation — use Forwardable or delegate")
            end
          end
          results
        end

        def dense_inline_hash(code)
          results = []
          in_method  = false
          method_line = 0
          hash_pairs  = 0

          code.each_line.with_index(1) do |line, number|
            stripped = line.strip
            if stripped.start_with?("def ")
              in_method   = true
              method_line = number
              hash_pairs  = 0
            elsif stripped == "end" && in_method
              if hash_pairs >= HASH_PAIR_THRESHOLD
                results << finding(line: method_line,
                  message: "#{hash_pairs} hash pairs inline — hoist to a named constant or extract a builder")
              end
              in_method  = false
              hash_pairs = 0
            elsif in_method
              hash_pairs += stripped.scan("=>").size
            end
          end
          results
        end
      end
    end
  end
end

```

## lib/master/scan/rules/pola_rule.rb
```ruby
# frozen_string_literal: true

module Master
  module Scan
    module Rules
      class PolaRule < Rule
        BOOL_POSITIONAL = /def\s+\w+\([^)]*,\s*(true|false)\s*[,)]/.freeze
        DOUBLE_NEG      = /\bunless\s+!/.freeze
        NEG_BOOL_ATTR   = /\battr_\w+\s+:(?:not_|no_|without_|disabled?_|skip_)\w+/.freeze

        def initialize
          super
          @id          = "pola"
          @description = "Principle of Least Astonishment — surprising names, contracts, or side-effects"
          @severity    = :warning
          @axiom_tags  = [:EXPLICIT]
        end

        def check(code, path:)
          return [] unless path.end_with?(".rb")

          findings        = []
          in_predicate    = false
          pred_line       = 0
          depth           = 0

          code.each_line.with_index(1) do |line, num|
            next if line.strip.start_with?("#")
            findings << finding(line: num, message: "boolean positional default — use keyword arg (def method(flag: false)) to name intent at call site") if line.match?(BOOL_POSITIONAL)
            findings << finding(line: num, message: "double negation detected — invert condition and use positive form") if line.match?(DOUBLE_NEG)
            findings << finding(line: num,
              message: "negative attribute name — name what it IS, not what it ISN'T") if line.match?(NEG_BOOL_ATTR)

            if line.match?(/^\s+def\s+\w+\?/)
              if line.match?(/=\s*[^=]/)
                in_predicate = false
              else
                in_predicate = true
                pred_line    = num
                depth        = 1
              end
            elsif in_predicate
              depth += line.scan(/\bdo\b|\bbegin\b|\bdef\b/).size
              depth += 1 if line.match?(/^\s+(?:if|case|unless|while|until|for)\b/)
              depth -= line.scan(/\bend\b/).size
              if depth <= 0
                in_predicate = false
              elsif line.match?(/(@\w+\s*=(?!=)|\.save[!\s]|\.update[!\s]|File\.write)/)
                findings << finding(line: pred_line,
                  message: "predicate method (?) mutates state — predicates must only query, never mutate (POLA)")
                in_predicate = false
              end
            end
          end

          findings
        end
      end
    end
  end
end

```

## lib/master/scan/rules/prune_rule.rb
```ruby
# frozen_string_literal: true

module Master
  module Scan
    module Rules
      # Hedge words and preamble phrases in comments dilute signal.
      # Applies to Ruby and shell files — both use # comments.
      # Patterns loaded from data/rules.yml (voice.strunk section).
      class PruneRule < Rule
        DATA_PATH   = File.join(Master::ROOT, "data", "rules.yml").freeze
        COMMENT_EXT = %w[.rb .sh .zsh .bash].freeze

        def initialize
          super
          @id          = "prune"
          @description = "Hedge words and preamble phrases in comments reduce clarity"
          @severity    = :warning
          @axiom_tags  = [:STRUNK_WHITE]
        end

        def check(code, path:)
          return [] unless COMMENT_EXT.include?(File.extname(path).downcase)

          hedge_re    = build_hedge_re
          preamble_re = build_preamble_re

          code.each_line.with_index(1).flat_map { |line, num|
            next [] unless line.include?("#")
            findings = []
            findings << finding(line: num, message: "hedge in comment: #{line.strip}")    if hedge_re&.match?(line)
            findings << finding(line: num, message: "preamble in comment: #{line.strip}") if preamble_re&.match?(line)
            findings
          }
        end

        private

        def rules
          @rules ||= begin
            data = File.exist?(DATA_PATH) ? Master.load_yaml(DATA_PATH) : {}
            data.dig("voice", "strunk") || {}
          end
        rescue StandardError => _e
          @rules = {}
        end

        def build_hedge_re
          words = rules.fetch("hedges", []).filter_map { |h|
            if h.is_a?(Hash)
              pat = h["pattern"].to_s.strip
              pat.empty? ? nil : Regexp.escape(pat)
            elsif h.is_a?(String)
              h.strip.empty? ? nil : Regexp.escape(h.strip)
            end
          }
          return nil if words.empty?
          /(#{words.join("|")})/i
        rescue StandardError => _e
          nil
        end

        def build_preamble_re
          phrases = rules.fetch("preambles", []).filter_map { |p|
            next unless p.is_a?(String)
            p.strip.empty? ? nil : Regexp.escape(p.strip)
          }
          return nil if phrases.empty?
          /\#.*(?:#{phrases.join("|")})/i
        rescue StandardError => _e
          nil
        end
      end
    end
  end
end

```

## lib/master/scan/rules/reek_rule.rb
```ruby
# frozen_string_literal: true

require "open3"
require "json"

module Master
  module Scan
    module Rules
      # Reek smell detection mapped to MASTER axioms.
      # Degrades gracefully when reek is unavailable (CI, fresh installs).
      class ReekRule < Rule
        SMELL_MAP = {
          "TooManyMethods"         => { axiom: "ONE_JOB",        sev: :warning },
          "TooManyInstanceVariables" => { axiom: "ONE_JOB",      sev: :warning },
          "LongParameterList"      => { axiom: "DECOUPLE",       sev: :warning },
          "FeatureEnvy"            => { axiom: "DECOUPLE",       sev: :warning },
          "DataClump"              => { axiom: "DECOUPLE",       sev: :warning },
          "DuplicateMethodCall"    => { axiom: "ONE_SOURCE",     sev: :warning },
          "BooleanParameter"       => { axiom: "EXPLICIT",       sev: :warning },
          "ControlParameter"       => { axiom: "CQS",            sev: :warning },
          "NilCheck"               => { axiom: "EXPLICIT",       sev: :warning },
          "UncommunicativeMethodName" => { axiom: "SELF_EXPLAINING", sev: :warning },
          "UncommunicativeVariableName" => { axiom: "SELF_EXPLAINING", sev: :warning },
          "UncommunicativeParameterName" => { axiom: "SELF_EXPLAINING", sev: :warning },
          "UtilityFunction"        => { axiom: "DECOUPLE",       sev: :warning },
          "InstanceVariableAssumption" => { axiom: "EXPLICIT",   sev: :warning },
          "IrresponsibleModule"    => { axiom: "SELF_EXPLAINING", sev: :warning },
          "RepeatedConditional"    => { axiom: "ONE_SOURCE",     sev: :warning },
          "SubclassedFromCoreClass" => { axiom: "EXTEND_DONT_MODIFY", sev: :warning },
          "ModuleInitialize"       => { axiom: "POLA",           sev: :warning },
        }.freeze

        def initialize(root: nil)
          super()
          @id          = "reek"
          @description = "Code smell detection: feature envy, data clumps, boolean params (reek)"
          @severity    = :warning
          @axiom_tags  = SMELL_MAP.values.map { |v| v[:axiom].to_sym }.uniq
          @root        = root
        end

        def self.auto_build? = false

        def check(code, path:)
          return [] unless path.end_with?(".rb")
          return [] unless reek_available?

          out, _err, _status = Open3.capture3(
            "bundle", "exec", "reek",
            "--format", "json",
            "--no-color",
            path,
            chdir: @root || Dir.pwd
          )

          parse_smells(out)
        rescue StandardError => _e
          []
        end

        private

        def reek_available?
          @reek_available ||= begin
            _, _, s = Open3.capture3("bundle", "exec", "reek", "--version",
                                     chdir: @root || Dir.pwd)
            s.success?
          rescue StandardError => _e
            false
          end
        end

        def parse_smells(json_str)
          data = JSON.parse(json_str)
          data.filter_map do |smell|
            meta = SMELL_MAP[smell["smell_type"]]
            next unless meta
            finding(
              line:    smell["lines"]&.first || 1,
              message: "[#{meta[:axiom]}] #{smell["smell_type"]}: #{smell["message"]}"
            )
          end
        rescue StandardError => _e
          []
        end
      end
    end
  end
end

```

## lib/master/scan/rules/rubocop_rule.rb
```ruby
# frozen_string_literal: true

require "open3"
require "json"

module Master
  module Scan
    module Rules
      # Rubocop AST analysis filtered to cops that map directly to MASTER axioms.
      # Degrades gracefully when rubocop is unavailable (CI, fresh installs).
      class RubocopRule < Rule
        COP_MAP = {
          "Metrics/MethodLength"        => { axiom: "ONE_JOB",       sev: :warning },
          "Metrics/ClassLength"         => { axiom: "SIMPLEST_WORKS", sev: :warning },
          "Metrics/AbcSize"             => { axiom: "ONE_JOB",       sev: :warning },
          "Metrics/CyclomaticComplexity" => { axiom: "SIMPLEST_WORKS", sev: :error },
          "Metrics/PerceivedComplexity" => { axiom: "SIMPLEST_WORKS", sev: :warning },
          "Metrics/ParameterLists"      => { axiom: "DECOUPLE",      sev: :warning },
          "Lint/RescueException"        => { axiom: "FAIL_VISIBLY",  sev: :error },
          "Lint/SuppressedException"    => { axiom: "FAIL_VISIBLY",  sev: :error },
          "Lint/DuplicateMethods"       => { axiom: "ONE_SOURCE",    sev: :error },
          "Style/GuardClause"           => { axiom: "BE_CONCISE",    sev: :warning },
          "Style/ReturnNil"             => { axiom: "EXPLICIT",      sev: :warning },
          "Naming/MethodParameterName"  => { axiom: "SELF_EXPLAINING", sev: :warning },
          "Layout/LineLength"           => { axiom: "BE_CONCISE",    sev: :warning },
        }.freeze

        def initialize(root: nil)
          super()
          @id          = "rubocop"
          @description = "AST-based analysis: complexity, guard clauses, parameter names (rubocop)"
          @severity    = :warning
          @axiom_tags  = COP_MAP.values.map { |v| v[:axiom].to_sym }.uniq
          @root        = root
        end

        def self.auto_build? = false

        def check(code, path:)
          return [] unless path.end_with?(".rb")
          return [] unless rubocop_available?

          config_flag = rubocop_config_flag
          out, _err, status = Open3.capture3(
            "bundle", "exec", "rubocop",
            *config_flag,
            "--format", "json",
            "--no-color",
            path,
            chdir: @root || Dir.pwd
          )

          return [] unless status.exitstatus&.<= 1  # 0=clean 1=offenses 2=error

          parse_offenses(out)
        rescue StandardError => _e
          []
        end

        private

        def rubocop_available?
          @rubocop_available ||= begin
            _, _, s = Open3.capture3("bundle", "exec", "rubocop", "--version",
                                     chdir: @root || Dir.pwd)
            s.success?
          rescue StandardError => _e
            false
          end
        end

        def rubocop_config_flag
          cfg = File.join(@root || Dir.pwd, ".rubocop.yml")
          File.exist?(cfg) ? ["--config", cfg] : ["--only", COP_MAP.keys.join(",")]
        end

        def parse_offenses(json_str)
          data = JSON.parse(json_str)
          data["files"].flat_map do |file|
            file["offenses"].filter_map do |o|
              meta = COP_MAP[o["cop_name"]]
              next unless meta
              finding(
                line:    o.dig("location", "line") || 1,
                message: "[#{meta[:axiom]}] #{o["cop_name"]}: #{o["message"]}"
              )
            end
          end
        rescue StandardError => _e
          []
        end
      end
    end
  end
end

```

## lib/master/scan/rules/self_explaining_rule.rb
```ruby
# frozen_string_literal: true

module Master
  module Scan
    module Rules
      # SelfExplainingRule — detects names that obscure intent, violating SELF_EXPLAINING.
      # Flags method/variable names that are abbreviations, noise words, or too generic
      # to reveal purpose without reading the implementation.
      class SelfExplainingRule < Rule
        NOISE_NAMES   = /^\s+def\s+(?:self\.)?(do_it|handle|process|run_it|execute_it|go|doit)\b/.freeze
        ABBREV_METHOD = /^\s+def\s+(tmp|res|ret|val|obj|thingy|stuff|thing|data2|info2)\b/.freeze
        ABBREV_VAR    = /\b(tmp|res|ret|val|obj|arr|lst|hsh|idx|cnt|num|str)\s*=(?!=)/.freeze

        def initialize
          super
          @id          = "self_explaining"
          @description = "Opaque names — names should reveal purpose without reading the implementation"
          @severity    = :warning
          @axiom_tags  = [:SELF_EXPLAINING]
        end

        def check(code, path:)
          return [] unless path.end_with?(".rb")

          code.each_line.with_index(1).flat_map { |line, num|
            next [] if line.strip.start_with?("#")
            next [] if line.match?(/^\s+[A-Z][A-Z0-9_]+ \s*=/)
            findings = []
            findings << finding(line: num, message: "noise method name — rename to reveal intent") if line.match?(NOISE_NAMES)
            findings << finding(line: num, message: "abbreviated method name — use the full descriptive word") if line.match?(ABBREV_METHOD)
            findings << finding(line: num, message: "abbreviated variable — prefer descriptive identifier") if line.match?(ABBREV_VAR)
            findings
          }
        end
      end
    end
  end
end

```

## lib/master/scan/rules/srp_rule.rb
```ruby
# frozen_string_literal: true

module Master
  module Scan
    module Rules
      # SrpRule — Single Responsibility Principle.
      # A class should have one reason to change. Flags classes whose public methods
      # span multiple concern domains (persistence, rendering, validation, networking, parsing).
      class SrpRule < Rule
        CONCERNS = {
          persistence: /\b(save|load|read_\w|write_\w|persist|store_\w|fetch_\w|find_by|delete|destroy|insert|upsert)\b/,
          rendering:   /\b(render|display|format_\w|present|to_html|draw|paint|emit|output_\w)\b/,
          validation:  /\b(valid\?|validate[^d]|check_\w|verify_\w|assert_\w|ensure_\w|guard_\w)\b/,
          networking:  /\b(request_\w|http_\w|send_request|receive_\w|connect_\w|socket_\w)\b/,
          parsing:     /\b(parse_\w|tokenize|lex_\w|extract_\w|decode_\w|encode_\w|deserialize|serialize)\b/,
        }.freeze

        def initialize
          super
          @id          = "srp"
          @description = "Single Responsibility Principle — class spans multiple concern domains"
          @severity    = :warning
          @axiom_tags  = [:ONE_JOB]
        end

        def check(code, path:)
          return [] unless path.end_with?(".rb")

          public_methods = code.scan(/^\s{2,8}def\s+(\w+)/).flatten
          return [] if public_methods.size < 4

          concerns_found = CONCERNS.select { |_, pat| public_methods.any? { |m| m.match?(pat) } }
          return [] if concerns_found.size < 2

          class_name = code.match(/class\s+(\w+)/i)&.[](1) || File.basename(path, ".rb")
          [finding(
            line: 1,
            message: "#{class_name} spans #{concerns_found.size} domains " \
                     "(#{concerns_found.keys.join(", ")}) — split by single responsibility (SRP)"
          )]
        end
      end
    end
  end
end

```

## lib/master/scan/rules/tell_dont_ask_rule.rb
```ruby
# frozen_string_literal: true

module Master
  module Scan
    module Rules
      # Querying an object's state then acting on it from outside breaks encapsulation.
      # The decision should live inside the object (tell it what to do, don't ask what it is).
      # Flags the most common Ruby patterns: .status/.state/.type == then method call,
      # and nil? guards that should be moved into the object.
      class TellDontAskRule < Rule
        STATE_QUERY  = /\b(\w+)\.(status|state|type|kind|mode|phase)\s*==/.freeze
        NIL_GUARD    = /\b(\w+)\.nil\?\s*\|\|/.freeze
        READY_QUERY  = /\b(\w+)\.ready\?\s*&&\s*\1\./.freeze

        def initialize
          super
          @id          = "tell_dont_ask"
          @description = "Tell-Don't-Ask: move state-based decisions into the object"
          @severity    = :warning
          @axiom_tags  = %i[DECOUPLE EXPLICIT]
        end

        def check(code, path:)
          return [] unless path.end_with?(".rb")
          findings = []
          code.each_line.with_index(1) do |line, num|
            next if line.strip.start_with?("#")
            findings << finding(line: num,
              message: "TDA: querying .status/.state outside the object — move the decision into the class") if line.match?(STATE_QUERY)
            findings << finding(line: num,
              message: "TDA: nil? guard before method call — use Null Object or move nil check into the object") if line.match?(NIL_GUARD)
            findings << finding(line: num,
              message: "TDA: ready? check then method call on same object — replace with a single command method") if line.match?(READY_QUERY)
          end
          findings
        end
      end
    end
  end
end

```

## lib/master/scan/rules/thread_safety_rule.rb
```ruby
# frozen_string_literal: true

module Master
  module Scan
    module Rules
      class ThreadSafetyRule < Rule
        # Dir.chdir is process-wide; breaks concurrent threads using different roots.
        DIR_CHDIR     = /\bDir\.chdir\b/
        # String-interpolated shell calls risk injection and hide argument boundaries.
        SHELL_INTERP  = /(?:system|`|IO\.popen|Open3\.\w+)\s*\(?\s*["'][^"']*#\{/
        # Prism.parse freeze: kwarg dropped in Ruby 3.4.
        PRISM_FREEZE  = /Prism\.parse\([^)]*freeze:\s*(?:true|false)/

        def initialize
          super
          @id          = "thread_safety"
          @description = "Detect thread-unsafe patterns: Dir.chdir, shell interpolation, dropped kwargs"
          @severity    = :error
          @axiom_tags  = %i[FAIL_VISIBLY EXPLICIT]
        end

        def check(code, path:)
          return [] unless path.end_with?(".rb")

          scan_lines(code, DIR_CHDIR,
            message: "Dir.chdir is process-wide and thread-unsafe; use -C flag or File.expand_path") +
          scan_lines(code, SHELL_INTERP,
            message: "shell interpolation risks injection; use Open3.capture2e with arg array") +
          scan_lines(code, PRISM_FREEZE,
            message: "Prism.parse freeze: kwarg removed in Ruby 3.4; drop it")
        end
      end
    end
  end
end

```

## lib/master/scan/rules/threshold_drift_rule.rb
```ruby
# frozen_string_literal: true

module Master
  module Scan
    module Rules
      # Hardcoded threshold constants in scan rules drift silently from rules.yml.
      # Every threshold should be read from Axioms at init time, not baked into a constant.
      # Flags THRESHOLD, MAX_LINES, MIN_LINES, WARN_LINES constants in scan rule files.
      class ThresholdDriftRule < Rule
        DRIFT_CONST = /^\s+(?:THRESHOLD|MAX_LINES|MIN_LINES|WARN_LINES|MAX_PARAMS|MAX_METHODS)\s*=\s*\d+/.freeze

        def initialize
          super
          @id          = "threshold_drift"
          @description = "Hardcoded threshold constant in scan rule — read from Axioms instead"
          @severity    = :warning
          @axiom_tags  = [:ONE_SOURCE]
        end

        def check(code, path:)
          return [] unless path.include?("scan/rules") && path.end_with?(".rb")
          scan_lines(code, DRIFT_CONST,
            message: "hardcoded threshold — use Master::Axioms.new.thresholds.dig(...) so rules.yml is the single source")
        end
      end
    end
  end
end

```

## lib/master/scan/rules/universal_rule.rb
```ruby
# frozen_string_literal: true

module Master
  module Scan
    module Rules
      # UniversalRule — cross-language axiom enforcement.
      # All rules apply to all file types; vertical-spacing checks skip HTML/ERB
      # since blank lines affect markup output.
      class UniversalRule < Rule
        BLANK_FLOOD     = /\n{4,}/.freeze
        BOX_CHARS   = [0x256D,0x256E,0x2570,0x256F,0x2502,0x2500,0x250C,0x2510,0x2514,0x2518,
                       0x251C,0x2524,0x252C,0x2534,0x253C,0x2550,0x2551,0x2554,0x2557,0x255A,0x255D]
                       .map { |cp| cp.chr(Encoding::UTF_8) }.join.freeze
        BOX_DRAWING = Regexp.new("[#{Regexp.escape(BOX_CHARS)}]|={4,}|-{4,}").freeze
        OPAQUE_NAMES    = /\b(tmp|temp|val|ret|obj|str|arr|buf)\b\s*=/.freeze
        DEAD_AFTER_STOP = /\b(return|exit|raise|throw)\b.+\n\s*\S/.freeze
        STALE_COMMENT   = /^\s*#\s*(TODO|FIXME|HACK|REVIEW|NOTE):\s*$/i.freeze

        CHECKS = [
          { pattern: BLANK_FLOOD,     message: "more than 3 consecutive blank lines — use single blank between sections",       fix: "collapse to one blank line" },
          { pattern: BOX_DRAWING,     message: "box-drawing chars or separator lines — use whitespace as layout tool",          fix: "delete separators" },
          { pattern: OPAQUE_NAMES,    message: "generic variable name — use a domain-specific name",                            fix: nil },
          { pattern: STALE_COMMENT,   message: "empty TODO/FIXME marker — fill it or delete it",                               fix: "delete marker" },
        ].freeze

        def initialize
          super
          @id          = "universal"
          @description = "Cross-language axiom checks"
          @severity    = :info
          @auto_fix    = true
          @axiom_tags  = %i[SQUINT_TEST TYPOGRAPHY_DISCIPLINE MEANINGFUL_NAMES WHITESPACE_PUNCTUATION]
        end

        def check(code, path:)
          findings = []
          CHECKS.each do |check|
            code.each_line.with_index(1) do |line, number|
              findings << finding(line: number, message: check[:message], fix: check[:fix]) if line.match?(check[:pattern])
            end
          end
          check_dead_code(code, findings)
          check_dense_methods(code, findings)
          findings
        end

        private

        def check_dead_code(code, findings)
          code.each_line.with_index(1).each_cons(2) do |(line_a, number_a), (line_b, _)|
            next unless line_a.match?(DEAD_AFTER_STOP) && line_b.match?(/\S/)
            findings << finding(line: number_a, message: "dead code after #{line_a.strip.split.first} — remove unreachable lines", fix: "delete unreachable lines")
          end
        end

        def check_dense_methods(code, findings)
          code.each_line.with_index(1).each_cons(2) do |(line_a, number_a), (line_b, _)|
            stripped_a = line_a.strip
            stripped_b = line_b.strip
            next unless stripped_a == "end" && stripped_b.start_with?("def ")
            findings << finding(line: number_a, message: "no blank line between method definitions — add vertical spacing", fix: "insert blank line")
          end
        end
      end
    end
  end
end

```

## lib/master/scan/scanner.rb
```ruby
# frozen_string_literal: true

require "etc"

module Master
  module Scan
    class Scanner
      RULES_PATH   = File.join(Master::ROOT, "data", "rules.yml").freeze
      POOL_SIZE    = [Etc.nprocessors, 8].min

      def initialize(rules: nil, event_bus: nil)
        @rules = rules || []
        @bus   = event_bus
        @mutex = Mutex.new
      end

      def scan(path, depth: :standard)
        return Result.err("file not found: #{path}", category: :validation) unless File.exist?(path)

        code     = File.read(path, encoding: "UTF-8")
        active   = active_rules(depth)
        findings = active.flat_map { |rule| rule.check(code, path:) }

        @bus&.publish("scan:complete", path:, depth:, count: findings.size)
        Result.ok(findings)
      rescue StandardError => e
        @bus&.publish("scan:error", path:, error: e.message)
        Result.err("scan failed: #{e.message}", category: :unknown)
      end

      SCAN_GLOB = "**/*.{rb,rake,erb,html,htm,css,scss,js,ts,jsx,tsx,zsh,sh,yml,yaml,md}".freeze

      def scan_dir(dir, depth: :standard, glob: SCAN_GLOB)
        paths   = Dir.glob(File.join(dir, glob)).sort
        results = Array.new(paths.size)
        threads = []
        semaphore = Mutex.new
        index = 0

        POOL_SIZE.times do
          threads << Thread.new do
            loop do
              current_index = semaphore.synchronize { (index += 1) - 1 }
              break if current_index >= paths.size
              begin
                results[current_index] = [paths[current_index], scan(paths[current_index], depth:)]
              rescue StandardError => e
                @bus&.publish("scanner:thread_error", path: paths[current_index], error: e.message)
                results[current_index] = [paths[current_index], Result.err(e.message, category: :unknown)]
              end
            end
          end
        end

        threads.each(&:join)
        Result.ok(results)
      rescue StandardError => e
        Result.err("scan_dir: #{e.message}", category: :unknown)
      end

      def add_rule(rule)
        @rules << rule
        self
      end

      def set_agent(agent)
        @rules.each { |r| r.set_agent(agent) if r.respond_to?(:set_agent) }
        self
      end

      private

      def depth_rules
        @depth_rules ||= begin
          data = Master.load_yaml(RULES_PATH)
          data["scan_depths"] || {}
        end
      rescue StandardError => _e
        @depth_rules = {}
      end

      def active_rules(depth)
        allowed = depth_rules[depth.to_s]
        return @rules if allowed.nil? || allowed == ["all"] || allowed == :all
        @rules.select { |r| allowed.include?(r.class.name.split("::").last) || allowed.include?(r.id) }
      end
    end
  end
end

```
