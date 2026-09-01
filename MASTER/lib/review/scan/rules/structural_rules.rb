# frozen_string_literal: true

require "prism"

module Master
  module Review
    module Scan
      module Rules
        # B05 FILE_LAYOUT — Ruby file order: frozen → require → module → class → public → private.
        class FileLayoutRule < Rule
          def initialize
            super()
            @id = "FILE_LAYOUT"
            @description = "frozen header → requires → module/class → public → private"
            @severity = :info
            @rule_tags = %i[PROXIMITY CONVENTION]
            @auto_fix = false
          end

          def check(code, path:)
            return [] unless path.to_s.end_with?(".rb", ".rake")
            findings = []
            lines = code.lines
            first_non_comment = lines.find_index { |l| !l.match?(/^\s*#|^\s*$/) }
            return [] unless first_non_comment
            unless lines.first&.include?("frozen_string_literal")
              findings << finding(line: 1, message: "missing # frozen_string_literal: true as first line")
            end
            private_idx = lines.find_index { |l| l.match?(/^\s+private\s*$|^\s+private\b/) }
            if private_idx
              public_def_after_private = lines[private_idx..].each_with_index.find do |l, i|
                l.match?(/^\s+def (?!self\.)/) && !l.match?(/^\s+def (?:initialize|to_s|inspect)\b/)
              end
              if public_def_after_private
                idx = private_idx + public_def_after_private[1] + 1
                findings << finding(line: idx, message: "public method def after private marker — move above private")
              end
            end
            findings
          end
        end

        # B06 EXPLICIT — implicit requires, magic coupling, method_missing without respond_to_missing?.
        class ExplicitRule < Rule
          def initialize
            super()
            @id = "EXPLICIT"
            @description = "no implicit requires or magic coupling"
            @severity = :warning
            @rule_tags = %i[EXPLICIT CONVENTION]
            @auto_fix = false
          end

          def check(code, path:)
            return [] unless path.to_s.end_with?(".rb", ".rake")
            findings = []
            findings.concat(scan_lines(code, /\bmethod_missing\b/, message: "method_missing without respond_to_missing? — add respond_to_missing?")) \
              if code.include?("method_missing") && !code.include?("respond_to_missing?")
            findings.concat(scan_lines(code, /\bconst_missing\b/, message: "const_missing — prefer explicit require"))
            findings.concat(scan_lines(code, /\bautoload\b/, message: "autoload — prefer explicit require_relative"))
            findings
          end

          private

          def scan_lines(src, pattern, message:)
            indexed_lines = src.lines.each_with_index
            indexed_lines.filter_map do |line, i|
              finding(line: i + 1, message:) if line.match?(pattern)
            end
          end
        end

        # B08 CYCLOMATIC_COMPLEXITY — methods with cyclomatic complexity > 10.
        class CyclomaticComplexityRule < Rule
          MAX_CC = 10
          CC_NODES = [
            Prism::IfNode, Prism::UnlessNode, Prism::WhileNode, Prism::UntilNode,
            Prism::ForNode, Prism::WhenNode, Prism::RescueNode, Prism::AndNode,
            Prism::OrNode
          ].freeze

          def initialize
            super()
            @id = "CYCLOMATIC_COMPLEXITY"
            @description = "cyclomatic complexity under 10 per method"
            @severity = :warning
            @rule_tags = %i[LINEARITY SMALL_PARTS]
            @auto_fix = false
          end

          def check_ast(ast, _code, path:)
            return [] unless ast
            findings = []
            visit(ast) do |node|
              next unless node.is_a?(Prism::DefNode)
              cc = 1 + count_cc_nodes(node)
              next if cc <= MAX_CC
              findings << finding(line: node.location.start_line,
                message: "method #{node.name} has cyclomatic complexity #{cc} (max #{MAX_CC}) — extract branches")
            end
            findings
          end

          private

          def visit(node, &block)
            return unless node.respond_to?(:child_nodes)
            block.call(node)
            node.child_nodes.compact.each { |c| visit(c, &block) }
          end

          def count_cc_nodes(node)
            return 0 unless node.respond_to?(:child_nodes)
            own = CC_NODES.include?(node.class) ? 1 : 0
            own + node.child_nodes.compact.sum { |c| count_cc_nodes(c) }
          end
        end

        # B09 PATTERN_EXTRACTION — code close to a named design pattern.
        class PatternExtractionRule < Rule
          BRANCH_THRESHOLD = 3
          PIPELINE_STEP_THRESHOLD = 4

          def initialize
            super()
            @id = "PATTERN_EXTRACTION"
            @description = "file is close to a named design pattern"
            @severity = :info
            @rule_tags = %i[DESIGN OPPORTUNITY]
            @auto_fix = false
          end

          def check_ast(ast, code, path:)
            return [] unless ast

            lines = code.lines
            findings = []
            visit(ast) { |node| findings << def_node_finding(node, lines) if node.is_a?(Prism::DefNode) }
            findings.compact
          end

          private

          def def_node_finding(node, lines)
            method_lines = lines[(node.location.start_line - 1)...node.location.end_line].join
            branch_count = branch_dispatch_count(method_lines)
            if branch_count >= BRANCH_THRESHOLD
              finding(
                line: node.location.start_line,
                message: "Strategy opportunity in #{node.name}: #{branch_count} dispatch branches — extract named handlers",
              )
            elsif pipeline_step_count(method_lines) >= PIPELINE_STEP_THRESHOLD
              finding(
                line: node.location.start_line,
                message: "Pipeline opportunity in #{node.name}: sequential transformations can be named stages",
              )
            end
          end

          def visit(node, &block)
            return unless node.respond_to?(:child_nodes)
            block.call(node)
            node.child_nodes.compact.each { |c| visit(c, &block) }
          end

          def branch_dispatch_count(src)
            src.lines.count { |line| line.match?(/^\s*(when|elsif)\b/) }
          end

          def pipeline_step_count(src)
            assignments = src.lines.filter_map do |line|
              match = line.match(/^\s*([a-z_]\w*)\s*=\s*(.+)$/)
              [match[1], match[2]] if match
            end
            return 0 if assignments.size < PIPELINE_STEP_THRESHOLD
            assignments.each_cons(PIPELINE_STEP_THRESHOLD).find { |group| chained_assignments?(group) }&.size.to_i
          end

          def chained_assignments?(group)
            names = group.map(&:first)
            return false unless names.uniq.size == names.size
            group.each_cons(2).all? { |left, right| right.last.match?(/\b#{Regexp.escape(left.first)}\b/) }
          end
        end

        # B10 DATA_CLASS — class with only attr_accessor and no real methods.
        class DataClassRule < Rule
          def initialize
            super()
            @id = "DATA_CLASS"
            @description = "data class with no behavior — use Struct or Data"
            @severity = :info
            @rule_tags = %i[SRP SOLID]
            @auto_fix = false
          end

          def check_ast(ast, _code, path:)
            return [] unless ast
            findings = []
            visit(ast) do |node|
              next unless node.is_a?(Prism::ClassNode)
              next unless node.body
              children = node.body.child_nodes.compact
              accessor_calls = children.count { |n| n.is_a?(Prism::CallNode) && %w[attr_accessor attr_reader attr_writer].include?(n.name.to_s) }
              real_defs = children.count { |n| n.is_a?(Prism::DefNode) && !%w[initialize to_s inspect].include?(n.name.to_s) }
              next unless accessor_calls >= 2 && real_defs == 0
              findings << finding(line: node.location.start_line,
                message: "#{node.constant_path.slice} has #{accessor_calls} accessors and no behavior — use Struct or Data.define")
            end
            findings
          end

          private

          def visit(node, &block)
            return unless node.respond_to?(:child_nodes)
            block.call(node)
            node.child_nodes.compact.each { |c| visit(c, &block) }
          end
        end
      end
    end
  end
end
module Master
  module Review
    module Scan
      module Rules
        # Enforces "core stays lean" as a live check, not just an aspiration --
        # matches OpenClaw's explicit policy (VISION.md: "we are generally
        # slimming down core... bar for adding optional plugins to core is
        # intentionally high"). MASTER's own lib/-vs-core/ split has been an
        # ongoing, unresolved tension; this at least stops lib/ root itself
        # from silently accumulating new files with no deliberate decision.
        class LibRootDisciplineRule < Rule
          ALLOWED_ROOT_FILES = %w[
            autonomy.rb builder.rb core.rb master.rb pressure_engine.rb
            result.rb security_error.rb unwrap_error.rb
          ].freeze

          def self.auto_build? = false

          def initialize(root: Master::ROOT)
            super()
            @id = "LIB_ROOT_DISCIPLINE"
            @description = "new files shouldn't land directly in lib/ root"
            @severity = :warning
            @rule_tags = %i[ABSTRACTION ARCHITECTURE]
            @auto_fix = false
            @lib_root = File.join(root, "lib")
          end

          def check(_code, path:)
            return [] unless in_lib_root?(path)
            return [] if ALLOWED_ROOT_FILES.include?(File.basename(path))

            [finding(
              line: 1,
              message: "#{File.basename(path)} added directly to lib/ root — move it into a " \
                "subsystem folder, or add it to LibRootDisciplineRule::ALLOWED_ROOT_FILES if it's genuinely core",
            )]
          end

          private

          def in_lib_root?(path)
            path.to_s.end_with?(".rb") && File.dirname(File.expand_path(path)) == @lib_root
          end
        end
      end
    end
  end
end

module Master
  module Review
    module Scan
      module Rules
      # Structural rules use Prism AST rather than line-by-line regex.
      # Each implements check_ast(ast, code, path:) for scanner integration.
      # All also implement check(code, path:) as fallback for non-Ruby files.

      # B01 SMALL_FILES — files over 300 lines (detect_structural: file_silhouette).
        class SmallFilesRule < Rule
          LIMIT = 300

          def initialize
            super()
            @id = "SMALL_FILES"
            @description = "files under 300 lines"
            @severity = :warning
            @rule_tags = %i[SMALL_PARTS]
            @auto_fix = false
          end

          def check(code, path:)
            count = code.lines.size
            return [] if count <= LIMIT
            [finding(line: 1, message: "file #{count} lines (limit #{LIMIT}) — split at module boundaries")]
          end
        end

      # B02 SMALL_FUNCTIONS — methods over 20 lines via Prism (detect_structural: long_method).
        class SmallFunctionsRule < Rule
          IDEAL = 10
          MAX = 20

          def initialize
            super()
            @id = "SMALL_FUNCTIONS"
            @description = "methods under 10 lines ideal, max 20"
            @severity = :warning
            @rule_tags = %i[SMALL_PARTS]
            @auto_fix = false
          end

          # Counts *code* lines, not the raw start..end span.
          #
          # The span version counted comments and blank lines toward method
          # length, which contradicts this rule's own description ("methods under
          # 10 lines ideal") — that is about how much logic a method holds, not
          # how well it is explained. In a codebase whose convention is a
          # paragraph of rationale above the tricky line, the effect was backwards:
          # Cli::TurnRouter.call was reported at 22 lines while containing 10 lines
          # of code and 8 lines of comment, so the only way to satisfy the rule was
          # to delete the explanation. Penalising documentation is the opposite of
          # what a quality gate should do.
          def check_ast(ast, code, path:)
            return [] unless ast

            lines = code.to_s.lines
            findings = []
            visit(ast) do |node|
              next unless node.is_a?(Prism::DefNode)

              len = code_length(node, lines)
              next if len <= MAX

              findings << finding(
                line: node.location.start_line,
                message: "method #{node.name} is #{len} code lines (max #{MAX}) — extract helpers",
              )
            end
            findings
          end

          private

          # Body only (between `def` and its `end`), excluding blank lines and
          # whole-line comments. A trailing comment on a code line still counts,
          # because that line carries code.
          # CodeMetrics, not a local copy: lint:spine and tools/ratchets.rb each
          # held their own line counter for the same ratchet, and this was the
          # third. tools/fixtures declares the answers it must give.
          def code_length(node, lines)
            CodeMetrics.method_code_lines(node, lines)
          end

          def visit(node, &block)
            return unless node.respond_to?(:child_nodes)
            block.call(node)
            node.child_nodes.compact.each { |c| visit(c, &block) }
          end
        end

      # B03 NO_GOD_CLASS — class with >10 public methods (detect_structural: god_class).
        class GodClassRule < Rule
          METHOD_LIMIT = 10
          LINE_LIMIT = 300

          def initialize
            super()
            @id = "NO_GOD_CLASS"
            @description = "no god classes"
            @severity = :error
            @rule_tags = %i[SOLID SRP]
            @auto_fix = false
          end

          def check_ast(ast, code, path:)
            return [] unless ast
            # A Minitest class's public methods ARE its tests — counting them
            # counts coverage as sin. SolidQueueProofTest carried 12 tests and
            # an error-severity god-class finding for it.
            return [] if path.to_s.match?(%r{/test/|/spec/|_test\.rb\z|_spec\.rb\z})
            lines = code.to_s.lines
            findings = []
            visit(ast) do |node|
              breach = class_breach(node, lines)
              findings << finding(line: node.location.start_line, message: breach) if breach
            end
            findings
          end

          private

          # The message for a class that is too big, or nil for one that is not.
          # Split out of check_ast because that method was 21 code lines against
          # DENSITY's max of 20 — the same law this file's neighbours declare.
          #
          # Code lines, not span. The raw span charged for rationale comments, so
          # a well-explained class breached while a stripped one passed — the
          # counter DENSITY and lint:spine already retired, surviving here.
          # Core::Constitution read 348 under it while holding 250 lines of code,
          # and the self_violation halted every /through fix stage; the only
          # "fix" the span offered was deleting the law's own reasoning.
          def class_breach(node, lines)
            return nil unless node.is_a?(Prism::ClassNode)

            public_defs = count_public_methods(node)
            name = node.constant_path.slice
            if public_defs > METHOD_LIMIT
              return "god class #{name} has #{public_defs} public methods (max #{METHOD_LIMIT}) — decompose"
            end

            line_count = CodeMetrics.method_code_lines(node, lines)
            return nil unless line_count > LINE_LIMIT

            "god class #{name} is #{line_count} code lines (max #{LINE_LIMIT}) — split at responsibility boundaries"
          end

          def visit(node, &block)
            return unless node.respond_to?(:child_nodes)
            block.call(node)
            node.child_nodes.compact.each { |c| visit(c, &block) }
          end

          def count_public_methods(class_node)
            CodeMetrics.public_method_count(class_node)
          end
        end

      # B07 NESTING_DEPTH — control-flow nesting deeper than 4 levels (detect_structural: nesting_depth).
      # Counts control flow only; module/class/def are namespacing and method scope, not the
      # LINEARITY concern — otherwise deep namespaces (Master::Review::Scan::Rules) flag every method.
        class NestingDepthRule < Rule
          MAX_DEPTH = 4

          NESTING_TYPES = [
            Prism::IfNode, Prism::UnlessNode, Prism::WhileNode,
            Prism::UntilNode, Prism::ForNode, Prism::CaseNode,
            Prism::BlockNode
          ].freeze

          def initialize
            super()
            @id = "NESTING_DEPTH"
            @description = "nesting depth under 4"
            @severity = :warning
            @rule_tags = %i[LINEARITY]
            @auto_fix = false
          end

          def check_ast(ast, _code, path:)
            return [] unless ast
            deep = []
            scan_depth(node: ast, depth: 0, violations: deep)
            deep.map { |line| finding(line:, message: "nesting depth exceeds #{MAX_DEPTH} — flatten with guard clauses or extract methods") }
          end

          private

          def scan_depth(node:, depth:, violations:)
            return unless node.respond_to?(:child_nodes)
            new_depth = NESTING_TYPES.include?(node.class) ? depth + 1 : depth
            if new_depth > MAX_DEPTH && violations.none? { |l| (l - node.location.start_line).abs < 3 }
              violations << node.location.start_line
            end
            node.child_nodes.compact.each { |child| scan_depth(node: child, depth: new_depth, violations:) }
          end
        end

      # B04 CQS — method that both mutates state and returns a meaningful value.
        class CqsRule < Rule
          def initialize
            super()
            @id = "CQS"
            @description = "command-query separation — mutate OR return, not both"
            @severity = :warning
            @rule_tags = %i[CQS CLEAN_CODE]
            @auto_fix = false
          end

          def check_ast(ast, _code, path:)
            return [] unless ast
            findings = []
            visit(ast) do |node|
              next unless node.is_a?(Prism::DefNode)
              body = node.body
              next unless body
              mutates = body_contains?(body, Prism::InstanceVariableWriteNode, Prism::InstanceVariableOperatorWriteNode)
              returns_value = body_has_explicit_return?(body)
              if mutates && returns_value
                findings << finding(line: node.location.start_line,
                  message: "method #{node.name} mutates state and returns a value — split into command and query")
              end
            end
            findings
          end

          private

          def visit(node, &block)
            return unless node.respond_to?(:child_nodes)
            block.call(node)
            node.child_nodes.compact.each { |c| visit(c, &block) }
          end

          def body_contains?(node, *types)
            return false unless node.respond_to?(:child_nodes)
            types.any? { |t| node.is_a?(t) } ||
              node.child_nodes.compact.any? { |c| body_contains?(c, *types) }
          end

          def body_has_explicit_return?(node)
            return false unless node.respond_to?(:child_nodes)
            return true if node.is_a?(Prism::ReturnNode) && node.arguments&.arguments&.any?
            node.child_nodes.compact.any? { |c| body_has_explicit_return?(c) }
          end
        end

      # SOLID literal proxies — data/rules.yml unit OPEN_CLOSED/LISKOV/
      # INTERFACE_SEGREGATION/DEPENDENCY_INVERSION previously had detect_semantic
      # only. These give each a same-file AST proxy; the semantic prompt still
      # carries the cases these heuristics miss.

        class OpenClosedRule < Rule
          MIN_BRANCHES = 3
          TYPE_PREDICATE = /\.(class|type|kind)\b/
          TYPE_CHECK = /\b(is_a\?|instance_of\?)\b/

          def initialize
            super()
            @id = "OPEN_CLOSED"
            @description = "case/when or is_a? chains that must grow on every new type"
            @severity = :warning
            @rule_tags = %i[SOLID OCP]
            @auto_fix = false
          end

          def check_ast(ast, _code, path:)
            return [] unless ast
            findings = []
            visit(ast) do |node|
              next unless node.is_a?(Prism::CaseNode)
              next unless node.conditions.size >= MIN_BRANCHES
              next unless type_dispatch?(node)
              findings << finding(line: node.location.start_line,
                message: "case dispatches on type across #{node.conditions.size} branches — new types require editing this switch; consider polymorphism or a lookup table")
            end
            findings
          end

          private

          def type_dispatch?(node)
            return true if node.predicate&.slice.to_s.match?(TYPE_PREDICATE)
            node.conditions.any? do |when_node|
              when_node.respond_to?(:conditions) &&
                when_node.conditions.any? { |c| c.slice.match?(TYPE_CHECK) }
            end
          end

          def visit(node, &block)
            return unless node.respond_to?(:child_nodes)
            block.call(node)
            node.child_nodes.compact.each { |c| visit(c, &block) }
          end
        end

        class LiskovRule < Rule
          def initialize
            super()
            @id = "LISKOV"
            @description = "subclass breaks the parent's contract via refused bequest or narrowed signature"
            @severity = :warning
            @rule_tags = %i[SOLID LSP]
            @auto_fix = false
          end

          def check_ast(ast, _code, path:)
            return [] unless ast
            classes = collect_classes(ast)
            findings = []
            classes.each_value do |info|
              parent = classes[info[:superclass]]
              next unless parent
              info[:methods].each do |name, def_node|
                parent_def = parent[:methods][name]
                next unless parent_def
                findings.concat(compare_methods(def_node, parent_def))
              end
            end
            findings
          end

          private

          def compare_methods(sub_def, parent_def)
            findings = []
            body_text = sub_def.body&.slice.to_s.strip
            if (match = body_text.match(/\Araise\s+(NotImplementedError|NoMethodError)\b/))
              findings << finding(line: sub_def.location.start_line,
                message: "#{sub_def.name} refuses the parent's contract (raises #{match[1]}) — use composition if substitutability fails")
            end
            sub_required = required_param_count(sub_def)
            parent_required = required_param_count(parent_def)
            if sub_required > parent_required
              findings << finding(line: sub_def.location.start_line,
                message: "#{sub_def.name} requires #{sub_required} args, parent requires #{parent_required} — narrows what callers can pass, breaking substitutability")
            end
            findings
          end

          def required_param_count(def_node)
            params = def_node.parameters
            return 0 unless params
            params.requireds.size + params.keywords.count { |k| k.is_a?(Prism::RequiredKeywordParameterNode) }
          end

          def collect_classes(ast)
            classes = {}
            visit(ast) do |node|
              next unless node.is_a?(Prism::ClassNode)
              methods = {}
              node.body&.body&.each do |child|
                methods[child.name] = child if child.is_a?(Prism::DefNode)
              end
              classes[node.name] = { superclass: node.superclass&.slice&.to_sym, methods: }
            end
            classes
          end

          def visit(node, &block)
            return unless node.respond_to?(:child_nodes)
            block.call(node)
            node.child_nodes.compact.each { |c| visit(c, &block) }
          end
        end

        class DependencyInversionRule < Rule
          COLLABORATOR_SUFFIX = /(Service|Client|Adapter|Gateway|Repository|Provider)\z/

          def initialize
            super()
            @id = "DEPENDENCY_INVERSION"
            @description = "constructor hardcodes a concrete collaborator instead of accepting it as a dependency"
            @severity = :warning
            @rule_tags = %i[SOLID DIP]
            @auto_fix = false
          end

          def check_ast(ast, _code, path:)
            return [] unless ast
            findings = []
            visit(ast) do |node|
              next unless node.is_a?(Prism::DefNode) && node.name == :initialize
              params = param_names(node)
              next unless node.body
              visit(node.body) do |call|
                next unless call.is_a?(Prism::CallNode) && call.name == :new && call.receiver
                const = call.receiver.slice
                next unless const.match?(COLLABORATOR_SUFFIX)
                next if params.include?(const.to_sym)
                findings << finding(line: call.location.start_line,
                  message: "#{const}.new hardcoded in initialize — inject as a constructor parameter instead")
              end
            end
            findings
          end

          private

          def param_names(def_node)
            params = def_node.parameters
            return [] unless params
            (params.requireds + params.optionals + params.keywords).filter_map do |p|
              p.respond_to?(:name) ? p.name : nil
            end
          end

          def visit(node, &block)
            return unless node.respond_to?(:child_nodes)
            block.call(node)
            node.child_nodes.compact.each { |c| visit(c, &block) }
          end
        end

        class InterfaceSegregationRule < Rule
          METHOD_LIMIT = 8

          def initialize
            super()
            @id = "INTERFACE_SEGREGATION"
            @description = "large module forces includers to stub methods they don't use"
            @severity = :warning
            @rule_tags = %i[SOLID ISP]
            @auto_fix = false
          end

          def check_ast(ast, _code, path:)
            return [] unless ast
            modules = collect_modules(ast)
            includers = collect_includers(ast)
            findings = []
            modules.each do |name, method_count|
              next if method_count <= METHOD_LIMIT
              users = includers[name] || []
              next if users.size < 2
              findings << finding(line: 1,
                message: "module #{name} has #{method_count} public methods, included by #{users.size} classes — split into smaller role-based modules")
            end
            findings
          end

          private

          def collect_modules(ast)
            modules = {}
            visit(ast) do |node|
              next unless node.is_a?(Prism::ModuleNode)
              count = node.body&.body.to_a.count { |c| c.is_a?(Prism::DefNode) }
              modules[node.name] = count
            end
            modules
          end

          def collect_includers(ast)
            includers = Hash.new { |h, k| h[k] = [] }
            visit(ast) do |node|
              next unless node.is_a?(Prism::ClassNode)
              node.body&.body&.each do |child|
                next unless child.is_a?(Prism::CallNode) && child.name == :include
                arg = child.arguments&.arguments&.first
                includers[arg.slice.to_sym] << node.name if arg
              end
            end
            includers
          end

          def visit(node, &block)
            return unless node.respond_to?(:child_nodes)
            block.call(node)
            node.child_nodes.compact.each { |c| visit(c, &block) }
          end
        end

        # Over-engineering, the deterministic half of engineering_fit: a class
        # whose every method only forwards to one other object carries a name and
        # a file and nothing else. Callers could hold that object directly. :info,
        # because a facade that adds a boundary on purpose is the exception the
        # reviewer decides — the rule surfaces the shape, not the verdict.
        class MiddleManRule < Rule
          MIN_METHODS = 3

          def initialize
            super()
            @id = "MIDDLE_MAN"
            @description = "a class that only forwards to one object adds a name, not behaviour"
            @severity = :info
            @rule_tags = %i[ENGINEERING_FIT ABSTRACTION]
            @auto_fix = false
          end

          def check_ast(ast, _code, path:)
            return [] unless ast

            class_nodes(ast).filter_map do |node|
              # initialize holds the delegate; it assigns, it does not forward, so
              # counting it would exempt every wrapper that has a constructor.
              defs = Array(node.body&.body).grep(Prism::DefNode).reject { |def_node| def_node.name == :initialize }
              next if defs.size < MIN_METHODS

              receivers = defs.map { |def_node| forwarded_receiver(def_node) }
              next if receivers.any?(&:nil?) || receivers.uniq.size != 1

              finding(line: node.location.start_line,
                message: "#{node.name} forwards all #{defs.size} methods to #{receivers.first} — inline it, or let callers hold #{receivers.first} directly")
            end
          end

          private

          def class_nodes(node, acc = [])
            return acc unless node.is_a?(Prism::Node)

            acc << node if node.is_a?(Prism::ClassNode)
            node.compact_child_nodes.each { |child| class_nodes(child, acc) }
            acc
          end

          # The one object a def forwards to, or nil the moment it does anything else.
          def forwarded_receiver(def_node)
            body = def_node.body
            return nil unless body.is_a?(Prism::StatementsNode) && body.body.size == 1

            call = body.body.first
            return nil unless call.is_a?(Prism::CallNode) && call.receiver

            receiver = call.receiver
            return receiver.name.to_s if receiver.is_a?(Prism::InstanceVariableReadNode)
            return receiver.name.to_s if receiver.is_a?(Prism::CallNode) && receiver.receiver.nil? && receiver.arguments.nil?

            nil
          end
        end

        StructuralRules = Module.new
      end
    end
  end
end
