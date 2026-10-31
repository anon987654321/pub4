# frozen_string_literal: true

require "prism"

module Master
  module Review
    module Scan
      module Laws
        # B05 FILE_LAYOUT — Ruby file order: frozen → require → module → class → public → private.
        class FileLayoutLaw < Detector
          # The three scopes Ruby resets method visibility in, plus the file itself.
          SCOPE_NODES = [
            Prism::ProgramNode, Prism::ClassNode, Prism::ModuleNode, Prism::SingletonClassNode
          ].freeze

          VISIBILITY_MARKERS = %w[public private protected].freeze


          def check(code, path:)
            return [] unless path.to_s.end_with?(".rb", ".rake")

            findings = header_finding(code)
            parsed = Prism.parse(code)
            return findings if parsed.failure?

            findings + public_below_private(parsed.value)
          end

          private

          # A shebang has to be the first line, so the header sits under it —
          # five executable tools in tools/ were reported for writing the only
          # order the kernel accepts.
          def header_finding(code)
            lines = code.lines
            return [] unless lines.any? { |line| !line.match?(/^\s*#|^\s*$/) }

            header = lines.first&.start_with?("#!") ? lines[1] : lines.first
            return [] if header&.include?("frozen_string_literal")

            [finding(line: 1, message: "missing # frozen_string_literal: true as first line")]
          end

          # Visibility is a property of the enclosing scope, so this reads scopes
          # rather than lines. The line-based reading called the first `def` under
          # every `private` a violation — 261 findings across MASTER, every one of
          # them a correctly private method — because a private section is what
          # `private` is for. What the law actually forbids is a method that is
          # still *public* below the marker, and there are two ways to write one:
          # re-open the scope with a bare `public`, or define a singleton method,
          # which `private` does not reach.
          def public_below_private(root)
            findings = []

            walk(root) do |node|
              next unless SCOPE_NODES.include?(node.class)

              findings.concat(scope_findings(scope_statements(node)))
            end
            findings
          end

          def scope_statements(node)
            body = node.is_a?(Prism::ProgramNode) ? node.statements : node.body
            body.is_a?(Prism::StatementsNode) ? body.body : []
          end

          def scope_findings(statements)
            visibility = :public
            sealed = false
            statements.filter_map do |statement|
              marker = visibility_marker(statement)

              if marker
                visibility = marker
                sealed ||= marker != :public
                next
              end
              next unless sealed && statement.is_a?(Prism::DefNode)

              exposed_method_finding(statement, visibility)
            end
          end

          def exposed_method_finding(node, visibility)
            receiver = node.receiver
            if receiver.nil?
              return unless visibility == :public

              finding(line: node.location.start_line,
                message: "public method #{node.name} after private marker — move above private")
            elsif receiver.is_a?(Prism::SelfNode)
              finding(line: node.location.start_line,
                message: "def self.#{node.name} below the private marker is still public — move it above")
            end
          end

          # A bare `private` changes the scope's default. `private :name` and
          # `private def name` name their subject and leave the default alone.
          def visibility_marker(statement)
            return unless statement.is_a?(Prism::CallNode)
            return unless statement.receiver.nil? && statement.arguments.nil? && statement.block.nil?
            return unless VISIBILITY_MARKERS.include?(statement.name.to_s)

            statement.name
          end
        end

        ::Law.define(:FILE_LAYOUT) do
          detector FileLayoutLaw
          tags %i[PROXIMITY CONVENTION]
          fix "frozen header → requires → module/class → public → private"
          proved_by "test/test_structural_shape_laws.rb"
        end

        # B06 EXPLICIT — implicit requires, magic coupling, method_missing without respond_to_missing?.
        class ExplicitLaw < Detector

          def check(code, path:)
            return [] unless path.to_s.end_with?(".rb", ".rake")
            findings = []
            if code.include?("method_missing") && !code.include?("respond_to_missing?")
              findings.concat(scan_lines(code, /\bmethod_missing\s*[(:]/,
                message: "method_missing without respond_to_missing? — add respond_to_missing?"))
            end
            findings.concat(scan_lines(code, /\bconst_missing\s*[(:]/,
              message: "const_missing — prefer explicit require"))
            findings.concat(scan_lines(code, /\bautoload\s*[(:]/,
              message: "autoload — prefer explicit require_relative"))
            findings
          end

          private

          def scan_lines(src, pattern, message:)
            indexed_lines = src.lines.each_with_index
            indexed_lines.filter_map do |line, i|
              next if line.lstrip.start_with?("#")
              next if line.match?(/scan:\s*intentional\b/)

              finding(line: i + 1, message:) if line.match?(pattern)
            end
          end
        end

        ::Law.define(:EXPLICIT) do
          detector ExplicitLaw
          tags %i[EXPLICIT CONVENTION]
          fix "no implicit requires or magic coupling"
          example_path "/repo/lib/example.rb"
          bad %(autoload :Thing, "thing"\n)
          good %(require_relative "thing"\n)
        end

        # B08 CYCLOMATIC_COMPLEXITY — methods with cyclomatic complexity > 10.
        class CyclomaticComplexityLaw < Detector
          MAX_CC = 10
          CC_NODES = [
            Prism::IfNode, Prism::UnlessNode, Prism::WhileNode, Prism::UntilNode,
            Prism::ForNode, Prism::WhenNode, Prism::RescueNode, Prism::AndNode,
            Prism::OrNode
          ].freeze


          def check_ast(ast, _code, path:)
            return [] unless ast
            findings = []
            walk(ast) do |node|
              next unless node.is_a?(Prism::DefNode)
              cc = 1 + count_cc_nodes(node)

              next if cc <= MAX_CC
              findings << finding(line: node.location.start_line,
                message: "method #{node.name} has cyclomatic complexity #{cc} (max #{MAX_CC}) — extract branches")
            end
            findings
          end

          private

          def count_cc_nodes(node)
            return 0 unless node.respond_to?(:child_nodes)
            own = CC_NODES.include?(node.class) ? 1 : 0
            own + node.child_nodes.compact.sum { |c| count_cc_nodes(c) }
          end
        end

        ::Law.define(:CYCLOMATIC_COMPLEXITY) do
          detector CyclomaticComplexityLaw
          tags %i[LINEARITY SMALL_PARTS]
          fix "cyclomatic complexity under 10 per method"
          proved_by "test/test_operator_lint.rb"
        end

        # B09 PATTERN_EXTRACTION — code close to a named design pattern.
        class PatternExtractionLaw < Detector
          BRANCH_THRESHOLD = 3
          PIPELINE_STEP_THRESHOLD = 4


          def check_ast(ast, code, path:)
            return [] unless ast

            lines = code.lines
            findings = []
            walk(ast) { |node| findings << def_node_finding(node, lines) if node.is_a?(Prism::DefNode) }
            findings.compact
          end

          private

          def def_node_finding(node, lines)
            method_lines = lines[(node.location.start_line - 1)...node.location.end_line].join
            branch_count = branch_dispatch_count(method_lines)

            if branch_count >= BRANCH_THRESHOLD
              finding(
                line: node.location.start_line,
                message: "Strategy opportunity in #{node.name}: #{branch_count} dispatch branches — " \
                  "extract named handlers",
              )
            elsif pipeline_step_count(method_lines) >= PIPELINE_STEP_THRESHOLD
              finding(
                line: node.location.start_line,
                message: "Pipeline opportunity in #{node.name}: sequential transformations can be named stages",
              )
            end
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

        ::Law.define(:PATTERN_EXTRACTION) do
          detector PatternExtractionLaw
          tags %i[DESIGN OPPORTUNITY]
          source "MASTER-native — extract recurring structure"
          ask "Is the code close to a known reusable pattern whose extraction would genuinely reduce complexity rather than add ceremony?"
          fix "Extract a pattern only when recurring structure earns the abstraction."
          bad <<~'X'
          if cache.hit?; cache.read; else; fetch; cache.write; end
          X
          good <<~'X'
          result = Cache.fetch(key) { fetch }
          X
          proved_by "test/test_pattern_extraction_law.rb"
        end

        # B10 DATA_CLASS — class with only attr_accessor and no real methods.
        class DataClassLaw < Detector

          def check_ast(ast, _code, path:)
            return [] unless ast
            findings = []
            walk(ast) do |node|
              next unless node.is_a?(Prism::ClassNode)
              next unless node.body
              children = node.body.child_nodes.compact
              accessor_calls = children.count { |n| n.is_a?(Prism::CallNode) && %w[attr_accessor attr_reader attr_writer].include?(n.name.to_s) }

              real_defs = children.count { |n| n.is_a?(Prism::DefNode) && !%w[initialize to_s inspect].include?(n.name.to_s) }
              next unless accessor_calls >= 2 && real_defs == 0
              findings << finding(line: node.location.start_line,
                message: "#{node.constant_path.slice} has #{accessor_calls} accessors and no behavior — " \
                  "use Struct or Data.define")
            end
            findings
          end

          private

        end

        ::Law.define(:DATA_CLASS) do
          detector DataClassLaw
          tags %i[SRP SOLID]
          source "Refactoring — Data Class (Fowler)"
          ask "Does this class mainly hold data while behavior that belongs with that data is scattered across other modules?"
          fix "Move cohesive behavior toward the data owner or replace the holder with a meaningful domain abstraction."
          bad <<~'X'
          class Money; attr_reader :cents; end; Tax.total(money)
          X
          good <<~'X'
          class Money; attr_reader :cents; def taxed(rate); cents * rate; end; end
          X
          proved_by "test/test_structural_shape_laws.rb"
        end

        # Enforces "core stays lean" as a live check, not just an aspiration --
        # matches OpenClaw's explicit policy (VISION.md: "we are generally
        # slimming down core... bar for adding optional plugins to core is
        # intentionally high"). MASTER's own lib/-vs-core/ split has been an
        # ongoing, unresolved tension; this at least stops lib/ root itself
        # from silently accumulating new files with no deliberate decision.
        class LibRootDisciplineLaw < Detector
          # autonomy.rb left the list with the subsystem it named. An allowance
          # for a file nobody can add back is the exemption-outlives-its-subject
          # shape this repo keeps writing down, and
          # test_the_allowance_names_lib_root_exactly holds the list to the tree
          # in both directions rather than leaving that to the comment.
          #
          # design.rb and ops.rb are each a whole subsystem that is one file with
          # no directory beside it.
          # device.rb (Termux capabilities), plugin.rb (the plugin manifest
          # loader) and snapshot.rb (the tree snapshot generator) are the same
          # shape: one file, one top-level Master constant that autoloads from it.
          # So are configuration_guard, convergence, face, gap, law_vocabulary,
          # md, pdf, phoenix and proof, each the single file of its constant.
          ALLOWED_ROOT_FILES = %w[
            builder.rb configuration_guard.rb convergence.rb core.rb design.rb device.rb
            face.rb gap.rb law_vocabulary.rb master.rb md.rb ops.rb pdf.rb phoenix.rb
            plugin.rb proof.rb result.rb security_error.rb snapshot.rb unwrap_error.rb
          ].freeze


          def initialize(root: Master::ROOT)
            super()
            @lib_root = File.join(root, "lib")
          end

          def check(_code, path:)
            return [] unless in_lib_root?(path)
            return [] if ALLOWED_ROOT_FILES.include?(File.basename(path))

            [finding(
              line: 1,
              message: "#{File.basename(path)} added directly to lib/ root — move it into a " \
                "subsystem folder, or add it to LibRootDisciplineLaw::ALLOWED_ROOT_FILES if it's genuinely core",
            )]
          end

          private

          def in_lib_root?(path)
            path.to_s.end_with?(".rb") && File.dirname(File.expand_path(path)) == @lib_root
          end
        end

        ::Law.define(:LIB_ROOT_DISCIPLINE) do
          detector LibRootDisciplineLaw
          tags %i[ABSTRACTION ARCHITECTURE]
          fix "new files shouldn't land directly in lib/ root"
          proved_by "test/test_lib_root_discipline_law.rb"
        end

      # Structural rules use Prism AST rather than line-by-line regex.
      # Each implements check_ast(ast, code, path:) for scanner integration.
      # All also implement check(code, path:) as fallback for non-Ruby files.

      # B01 SMALL_FILES — files over 300 lines (detect_structural: file_silhouette).
      #
      # The fix it names is a split at module boundaries, so it reads files that
      # have modules. A locale, a layout snapshot, a lockfile, a notebook or a
      # document has no such boundary, and its length is its content. JavaScript
      # is JS_MODULE_SIZE's, which asks the same question with the vendored
      # bundles set aside, so reading it here reported every long script twice.
        class SmallFilesLaw < Detector
          LIMIT = 300

          NOT_MODULAR = %w[json yaml markdown javascript].freeze
          DATA_EXTENSIONS = %w[.lock .txt .conf .ipynb .csv].freeze


          def check(code, path:)
            return [] if NOT_MODULAR.include?(language(path.to_s).to_s)
            return [] if DATA_EXTENSIONS.include?(File.extname(path.to_s))

            count = code.lines.size
            return [] if count <= LIMIT
            [finding(line: 1, message: "file #{count} lines (limit #{LIMIT}) — split at module boundaries",
                     blast_radius: SPANS_FILES)]
          end
        end

        ::Law.define(:SMALL_FILES) do
          detector SmallFilesLaw
          tags %i[SMALL_PARTS]
          fix "files under 300 lines"
          proved_by "test/test_scan_law_contracts.rb"
        end

      # B02 SMALL_FUNCTIONS — methods over 20 lines via Prism (detect_structural: long_method).
        class SmallFunctionsLaw < Detector
          IDEAL = 10
          MAX = 20


          # Counts *code* lines, not the raw start..end span.
          #
          # The span version counted comments and blank lines toward method
          # length, which contradicts this law's own description ("methods under
          # 10 lines ideal") — that is about how much logic a method holds, not
          # how well it is explained. In a codebase whose convention is a
          # paragraph of rationale above the tricky line, the effect was backwards:
          # Cli::TurnRouter.call was reported at 22 lines while containing 10 lines
          # of code and 8 lines of comment, so the only way to satisfy the law was
          # to delete the explanation. Penalising documentation is the opposite of
          # what a quality check should do.
          def check_ast(ast, code, path:)
            return [] unless ast

            lines = code.to_s.lines
            findings = []
            walk(ast) do |node|
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
          # third. test/fixtures declares the answers it must give.
          def code_length(node, lines)
            CodeMetrics.method_code_lines(node, lines)
          end

        end

        ::Law.define(:SMALL_FUNCTIONS) do
          detector SmallFunctionsLaw
          tags %i[SMALL_PARTS]
          fix "methods under 10 lines ideal, max 20"
          proved_by "test/test_scan_law_contracts.rb"
        end

      # B03 NO_GOD_CLASS — class with >10 public methods (detect_structural: god_class).
        class GodClassLaw < Detector
          METHOD_LIMIT = 10
          LINE_LIMIT = 300


          def check_ast(ast, code, path:)
            return [] unless ast
            # A Minitest class's public methods ARE its tests — counting them
            # counts coverage as sin. SolidQueueProofTest carried 12 tests and
            # an error-severity god-class finding for it.
            return [] if path.to_s.match?(%r{/test/|/spec/|_test\.rb\z|_spec\.rb\z})

            lines = code.to_s.lines
            classes(ast).filter_map do |name, nodes|
              breach = class_breach(name.split("::").last, nodes, lines)
              finding(line: nodes.first.location.start_line, message: breach, blast_radius: SPANS_FILES) if breach
            end
          end

          private

          # Every `class X` block in the file, grouped by the class it opens.
          #
          # The walk judged one AST node at a time, so a class written as a
          # scaffold and reopened — `class Propose; end` at the top, the methods
          # in a second block below — was measured twice at half its size, and
          # merging those blocks made the same class breach without one method
          # being added. The rule was reading source layout rather than the
          # class, and it read it backwards: the more scattered the file, the
          # more lenient the verdict.
          #
          # Keyed on the full lexical name, so two different `Foo` under two
          # modules in one file stay two classes.
          def classes(node, prefix = [], acc = Hash.new { |hash, key| hash[key] = [] })
            return acc unless node.is_a?(Prism::Node)

            named = node.is_a?(Prism::ClassNode) || node.is_a?(Prism::ModuleNode)
            inner = named ? prefix + [node.constant_path.slice] : prefix
            acc[inner.join("::")] << node if node.is_a?(Prism::ClassNode)
            node.compact_child_nodes.each { |child| classes(child, inner, acc) }
            acc
          end

          # The message for a class that is too big, or nil for one that is not.
          # Split out of check_ast because that method was 21 code lines against
          # DENSITY's max of 20 — the same law this file's neighbours declare.
          #
          # Code lines, not span. The raw span charged for rationale comments, so
          # a well-explained class breached while a stripped one passed — the
          # counter DENSITY and lint:spine already retired, surviving here.
          # Core::Constitution read 348 under it while holding 250 lines of code,
          # and the self_violation halted every /review fix stage; the only
          # "fix" the span offered was deleting the law's own reasoning.
          def class_breach(name, nodes, lines)
            public_defs = nodes.sum { |node| CodeMetrics.public_method_count(node) }

            if public_defs > METHOD_LIMIT
              return "god class #{name} has #{public_defs} public methods (max #{METHOD_LIMIT}) — decompose"
            end

            line_count = nodes.sum { |node| CodeMetrics.method_code_lines(node, lines) }
            return unless line_count > LINE_LIMIT

            "god class #{name} is #{line_count} code lines (max #{LINE_LIMIT}) — split at responsibility boundaries"
          end
        end

        ::Law.define(:NO_GOD_CLASS) do
          detector GodClassLaw
          tags %i[SOLID SRP]
          source "Refactoring code smell: Large Class / God Object (Fowler)"
          ask "Does one class accumulate unrelated responsibilities that should have separate owners?"
          fix "Decompose into focused objects with explicit responsibilities."
          bad <<~'X'
          class Application; def users; end; def billing; end; def render; end; def mail; end; end
          X
          good <<~'X'
          class Users; end; class Billing; end
          X
          proved_by "test/test_scan_law_contracts.rb"
        end

      # B07 NESTING_DEPTH — control-flow nesting deeper than 4 levels (detect_structural: nesting_depth).
      # Counts control flow only; module/class/def are namespacing and method scope, not the
      # LINEARITY concern — otherwise deep namespaces (Master::Review::Scan::Laws) flag every method.
        class NestingDepthLaw < Detector
          MAX_DEPTH = 4

          NESTING_TYPES = [
            Prism::IfNode, Prism::UnlessNode, Prism::WhileNode,
            Prism::UntilNode, Prism::ForNode, Prism::CaseNode,
            Prism::BlockNode
          ].freeze


          def check_ast(ast, _code, path:)
            return [] unless ast
            deep = []
            scan_depth(node: ast, depth: 0, violations: deep)
            message = "nesting depth exceeds #{MAX_DEPTH} — flatten with guard clauses or extract methods"
            deep.map { |line| finding(line:, message:) }
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

        ::Law.define(:NESTING_DEPTH) do
          detector NestingDepthLaw
          tags %i[LINEARITY]
          fix "nesting depth under 4"
          proved_by "test/test_structural_shape_laws.rb"
        end

      # B04 CQS — method that both mutates state and returns a meaningful value.
        class CqsLaw < Detector

          def check_ast(ast, _code, path:)
            return [] unless ast
            findings = []
            walk(ast) do |node|
              next unless node.is_a?(Prism::DefNode)
              body = node.body
              next unless body
              mutates = body_contains?(body, Prism::InstanceVariableWriteNode, Prism::InstanceVariableOperatorWriteNode)

              returns_value = body_has_explicit_return?(body)
              if mutates && returns_value && !memoized_reader?(body)
                findings << finding(line: node.location.start_line,
                  message: "method #{node.name} mutates state and returns a value — split into command and query")
              end
            end
            findings
          end

          private

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

          # A memoized reader deliberately writes absent state and returns the
          # resulting value. Recognize both the guard-and-assign form and ||= so
          # CQS does not classify cache initialization as a mixed command/query.
          def memoized_reader?(body)
            writes = child_nodes_of(body, Prism::InstanceVariableWriteNode, Prism::InstanceVariableOperatorWriteNode)
            return false unless writes.one?

            write = writes.first
            name = write.name.to_s
            returns = child_nodes_of(body, Prism::ReturnNode)
            matching = returns.select do |node|
              args = node.arguments&.arguments
              args&.one? && args.first.is_a?(Prism::InstanceVariableReadNode) &&
                args.first.name.to_s == name
            end
            return false unless returns.any? && matching.size == returns.size

            return true if write.is_a?(Prism::InstanceVariableOperatorWriteNode)

            reads = child_nodes_of(body, Prism::InstanceVariableReadNode)
            reads.any? { |node| node.name.to_s == name && node.location.start_offset < write.location.start_offset } &&
              matching.any? { |node| node.location.start_offset < write.location.start_offset }
          end

          def child_nodes_of(node, *types)
            return [] unless node.respond_to?(:child_nodes)

            matches = []
            matches << node if types.include?(node.class)
            node.child_nodes.compact.each { |child| matches.concat(child_nodes_of(child, *types)) }
            matches
          end
        end

        ::Law.define(:CQS) do
          detector CqsLaw
          tags %i[CQS CLEAN_CODE]
          fix "command-query separation — mutate OR return, not both"
          proved_by "test/test_scan_law_contracts.rb"
        end

      # SOLID literal proxies — data/laws.yml unit OPEN_CLOSED/LISKOV/
      # INTERFACE_SEGREGATION/DEPENDENCY_INVERSION previously had detect_semantic
      # only. These give each a same-file AST proxy; the semantic prompt still
      # carries the cases these heuristics miss.

        class OpenClosedLaw < Detector
          MIN_BRANCHES = 3
          TYPE_PREDICATE = /\.(class|type|kind)\b/

          # No trailing \b. A word boundary needs a word character on one side,
          # and `?` is not one — so `\bis_a\?\b` required a word character right
          # after the question mark, which no call has: `is_a?(Header)` and
          # `is_a? Header` both continue with a non-word character. The clause
          # could not match any spelling of the method it names, so half of what
          # the description promises has never fired. The leading \b stays and
          # does work, keeping `foo_is_a?` out.
          TYPE_CHECK = /\b(is_a\?|instance_of\?)/


          def check_ast(ast, _code, path:)
            return [] unless ast
            findings = []
            walk(ast) do |node|
              next unless node.is_a?(Prism::CaseNode)
              next unless node.conditions.size >= MIN_BRANCHES

              next unless type_dispatch?(node)
              findings << finding(line: node.location.start_line,
                message: "case dispatches on type across #{node.conditions.size} branches — new types require " \
                  "editing this switch; consider polymorphism or a lookup table")
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

        end

        ::Law.define(:OPEN_CLOSED) do
          detector OpenClosedLaw
          tags %i[SOLID OCP]
          source "Open-Closed Principle (Bertrand Meyer; SOLID)"
          ask "Must existing core code be modified whenever a new supported variant is added?"
          fix "Extend through stable interfaces, registries, or composition where that reduces repeated core edits."
          bad <<~'X'
          case format; when :json; render_json; when :xml; render_xml; end
          X
          good <<~'X'
          renderers.fetch(format).call(document)
          X
          proved_by "test/test_solid_laws.rb"
        end

        class LiskovLaw < Detector

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
                message: "#{sub_def.name} refuses the parent's contract (raises #{match[1]}) — " \
                  "use composition if substitutability fails")
            end
            sub_required = required_param_count(sub_def)

            parent_required = required_param_count(parent_def)
            if sub_required > parent_required
              findings << finding(line: sub_def.location.start_line,
                message: "#{sub_def.name} requires #{sub_required} args, parent requires #{parent_required} — " \
                  "narrows what callers can pass, breaking substitutability")
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
            walk(ast) do |node|
              next unless node.is_a?(Prism::ClassNode)
              methods = {}

              node.body&.body&.each do |child|
                methods[child.name] = child if child.is_a?(Prism::DefNode)
              end
              classes[node.name] = { superclass: node.superclass&.slice&.to_sym, methods: }
            end
            classes
          end

        end

        ::Law.define(:LISKOV) do
          detector LiskovLaw
          tags %i[SOLID LSP]
          source "Liskov Substitution Principle (Barbara Liskov, 1987)"
          ask "Does a subtype violate assumptions or guarantees established by the type it replaces?"
          fix "Make subtype behavior satisfy the established contract or use a different abstraction."
          bad <<~'X'
          class ReadOnlyStore < Store; def save(x); raise "no"; end; end
          X
          good <<~'X'
          class ReadOnlyStore < ReadStore; end
          X
          proved_by "test/test_solid_laws.rb"
        end

        class DependencyInversionLaw < Detector
          COLLABORATOR_SUFFIX = /(Service|Client|Adapter|Gateway|Repository|Provider)\z/


          def check_ast(ast, _code, path:)
            return [] unless ast
            findings = []
            walk(ast) do |node|
              next unless node.is_a?(Prism::DefNode) && node.name == :initialize
              params = param_names(node)
              next unless node.body
              walk(node.body) do |call|
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

        end

        ::Law.define(:DEPENDENCY_INVERSION) do
          detector DependencyInversionLaw
          tags %i[SOLID DIP]
          source "SOLID — Dependency Inversion Principle"
          ask "Does high-level policy directly instantiate concrete dependencies that should be replaceable?"
          fix "Depend on stable abstractions and inject concrete implementations at the boundary."
          bad <<~'X'
          class Checkout; def call; Stripe::Charge.create; end; end
          X
          good <<~'X'
          class Checkout; def initialize(payments:); @payments = payments; end; end
          X
          proved_by "test/test_solid_laws.rb"
        end

        class InterfaceSegregationLaw < Detector
          METHOD_LIMIT = 8


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
                message: "module #{name} has #{method_count} public methods, included by #{users.size} classes — " \
                  "split into smaller role-based modules")
            end
            findings
          end

          private

          def collect_modules(ast)
            modules = {}
            walk(ast) do |node|
              next unless node.is_a?(Prism::ModuleNode)
              count = node.body&.body.to_a.count { |c| c.is_a?(Prism::DefNode) }
              modules[node.name] = count
            end
            modules
          end

          def collect_includers(ast)
            includers = Hash.new { |h, k| h[k] = [] }
            walk(ast) do |node|
              next unless node.is_a?(Prism::ClassNode)
              node.body&.body&.each do |child|
                next unless child.is_a?(Prism::CallNode) && child.name == :include

                arg = child.arguments&.arguments&.first
                includers[arg.slice.to_sym] << node.name if arg
              end
            end
            includers
          end

        end

        ::Law.define(:INTERFACE_SEGREGATION) do
          detector InterfaceSegregationLaw
          tags %i[SOLID ISP]
          source "SOLID — Interface Segregation"
          ask "Does an interface force implementations to stub or ignore methods they do not need?"
          fix "Split broad interfaces into focused contracts."
          bad <<~'X'
          class Printer; def print; end; def scan; raise NotImplementedError; end; end
          X
          good <<~'X'
          Printable = Data.define; Scannable = Data.define
          X
          proved_by "test/test_solid_laws.rb"
        end

        # Over-engineering, the deterministic half of engineering_fit: a class
        # whose every method only forwards to one other object carries a name and
        # a file and nothing else. Callers could hold that object directly. :info,
        # because a facade that adds a boundary on purpose is the exception the
        # reviewer decides — the law surfaces the shape, not the verdict.
        class MiddleManLaw < Detector
          MIN_METHODS = 3


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
                message: "#{node.name} forwards all #{defs.size} methods to #{receivers.first} — " \
                  "inline it, or let callers hold #{receivers.first} directly")
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
            return unless body.is_a?(Prism::StatementsNode) && body.body.size == 1

            call = body.body.first
            return unless call.is_a?(Prism::CallNode) && call.receiver

            receiver = call.receiver
            return receiver.name.to_s if receiver.is_a?(Prism::InstanceVariableReadNode)
            return receiver.name.to_s if receiver.is_a?(Prism::CallNode) &&
                                         receiver.receiver.nil? && receiver.arguments.nil?

            nil
          end
        end

        ::Law.define(:MIDDLE_MAN) do
          detector MiddleManLaw
          tags %i[ENGINEERING_FIT ABSTRACTION]
          source "Refactoring — Middle Man (Fowler)"
          ask "Does this class mostly delegate methods to another object without adding meaningful policy?"
          fix "Remove the unnecessary middle layer or give it a real abstraction."
          bad <<~'X'
          def name; @user.name; end; def email; @user.email; end
          X
          good <<~'X'
          attr_reader :user
          X
          proved_by "test/test_structural_shape_laws.rb"
        end

        StructuralRules = Module.new
      end
    end
  end
end
