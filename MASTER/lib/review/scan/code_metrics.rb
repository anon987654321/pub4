# frozen_string_literal: true

module Master
  module Review
    module Scan
      # How this repo counts code. One implementation, because there were three.
      #
      # `rake lint:spine` and `tools/ratchets.rb` each carried their own copy of
      # the non-blank-non-comment line count — for the same ratchet, reported in
      # the same table. `SmallFunctionsRule` carried a third for method bodies.
      # They happened to agree; nothing made them.
      #
      # Counting is also where a throwaway script is most likely to be quietly
      # wrong. A hand-rolled method-length counter that treats `def x = expr`
      # as running to the next `end` reports a tightly-factored file as sprawling,
      # and the number looks plausible enough to reason from. tools/fixtures/
      # declares the right answers for cases like that and `rake lint:instruments`
      # holds this module to them.
      module CodeMetrics
        module_function

        # Non-blank, non-comment. A trailing comment on a code line still counts,
        # because that line carries code.
        def code_line?(line)
          stripped = line.strip
          !stripped.empty? && !stripped.start_with?("#")
        end

        def code_lines(source)
          source.to_s.lines.count { |line| code_line?(line) }
        end

        # Lines that exist only because Zeitwerk maps a path to a constant.
        #
        # `module Master` / `module Ground` / `module Policy` wrapping one nested
        # module carry no implementation; the loader requires them and the file
        # would not resolve without them. Counting them made every structural
        # improvement cost two lines per file, so lint:spine and lint:cohesion
        # pulled against each other and cohesion lost by default — three rounds
        # of regrouping were paid for by luck, then by the last orphan in lib/,
        # then by a budget raise.
        #
        # Only `module`, and only when its body is exactly one module or class.
        # A module holding a constant, a method, or two children is doing work
        # and counts. A `class` wrapping a class is a design choice nothing
        # forced, and counts too.
        def namespace_lines(source)
          require "prism"
          result = Prism.parse(source.to_s)
          return 0 unless result.success?

          count_namespaces(result.value)
        end

        def count_namespaces(node)
          return 0 unless node.respond_to?(:child_nodes)

          own = pure_namespace?(node) ? 2 : 0
          node.child_nodes.compact.sum(own) { |child| count_namespaces(child) }
        end

        # Two lines: the `module` and its `end`.
        def pure_namespace?(node)
          return false unless node.is_a?(Prism::ModuleNode)

          statements = node.body
          return false unless statements.is_a?(Prism::StatementsNode)
          return false unless statements.body.size == 1

          statements.body.first.is_a?(Prism::ModuleNode) || statements.body.first.is_a?(Prism::ClassNode)
        end

        # What lint:spine bounds: code minus the loader's ceremony.
        def body_lines(source) = code_lines(source) - namespace_lines(source)

        def body_lines_in(dir)
          Dir.glob(File.join(dir, "**", "*.rb")).sum { |file| body_lines(File.read(file)) }
        end

        # A method's body only: between `def` and its `end`, blank lines and
        # whole-line comments excluded.
        #
        # The span version counted comments toward method length, which
        # contradicts the rule's own description — that is about how much logic a
        # method holds, not how well it is explained. Cli::TurnRouter.call was
        # reported at 22 lines while holding 10 of code and 8 of comment, so the
        # only way to pass was to delete the explanation.
        #
        # An endless method (`def x = expr`) has start_line == end_line and
        # therefore a body of zero lines, which is the case a regex counter gets
        # wrong by scanning forward to the next `end`.
        def method_code_lines(node, lines)
          first = node.location.start_line
          last = node.location.end_line
          return 0 if last <= first

          (lines[first...(last - 1)] || []).count { |line| code_line?(line) }
        end

        # The public surface of one class or module.
        #
        # NO_GOD_CLASS is the reader, so this number decides whether a class is
        # reported as too large — and it was read off a stop marker rather than
        # off Ruby's visibility model. The walk ended at the first `private` or
        # `protected`, which is not what either keyword does:
        #
        #   * a `public` below `private` re-opens the scope, and every method
        #     after it went uncounted
        #   * `protected` was treated as end-of-class
        #   * `def self.x` below `private` is still public — `private` moves the
        #     instance-method default and does not reach the singleton stream —
        #     and the walk had already stopped
        #   * `private def x` and `public def x` are CallNodes wrapping the
        #     DefNode, so neither was ever counted
        #   * `class << self` has its own default and was invisible
        #
        # Every one of those undercounts, so the god-class rule has been reading
        # a floor rather than a surface.
        #
        # `module_function` is deliberately not modelled: it makes the instance
        # copy private and the module copy public, so the method stays on the
        # public surface and counting it once is the right answer already.
        def public_method_count(class_node)
          return 0 unless class_node.respond_to?(:body) && class_node.body

          VisibilityScope.new(VisibilityScope.statements(class_node.body)).count
        end

        # Visibility for the statements of one scope, in Ruby's terms.
        #
        # Two streams, because `private` moves one of them: instance methods
        # follow the running default, singleton methods (`def self.x`) follow
        # their own and are reached by `private_class_method`. Inside
        # `class << self` a bare `def` is a singleton method, which is why the
        # scope knows which stream is its own rather than assuming instance.
        class VisibilityScope
          MARKERS = %w[public protected private].freeze
          CLASS_MARKERS = { "private_class_method" => :private, "public_class_method" => :public }.freeze

          def self.statements(body)
            body.is_a?(Prism::StatementsNode) ? body.body : Array(body)
          end

          def initialize(statements, singleton_scope: false)
            @statements = statements
            @own_stream = singleton_scope ? :singleton : :instance
            @default = { instance: :public, singleton: :public }
            @named = { instance: {}, singleton: {} }
          end

          # Two passes. The named forms are retroactive — `private :foo` sits
          # below the `def foo` it hides — so a single forward pass counts a
          # method public before it learns otherwise.
          def count
            collect_named
            @statements.sum { |statement| tally(statement) }
          end

          private

          def collect_named
            @statements.each do |statement|
              next unless statement.is_a?(Prism::CallNode) && statement.receiver.nil?

              names = symbol_arguments(statement)
              next if names.empty?

              stream, visibility = named_target(statement.name.to_s)
              next unless stream

              names.each { |name| @named[stream][name] = visibility }
            end
          end

          def named_target(name)
            return [@own_stream, name.to_sym] if MARKERS.include?(name)
            return [:singleton, CLASS_MARKERS[name]] if CLASS_MARKERS.key?(name)

            [nil, nil]
          end

          def tally(statement)
            return nested_singleton(statement) if own_singleton_class?(statement)
            return tally_call(statement) if statement.is_a?(Prism::CallNode)
            return 0 unless statement.is_a?(Prism::DefNode)

            visible?(statement) ? 1 : 0
          end

          def tally_call(call)
            return 0 unless call.receiver.nil?

            name = call.name.to_s
            if (definition = inline_definition(call))
              return inline_visibility(name, definition) == :public ? 1 : 0
            end
            # A bare marker moves this scope's own default. `private :foo` has
            # arguments and was handled in the first pass.
            @default[@own_stream] = name.to_sym if MARKERS.include?(name) && call.arguments.nil?
            0
          end

          def inline_definition(call)
            return nil unless MARKERS.include?(call.name.to_s) || CLASS_MARKERS.key?(call.name.to_s)

            arguments = Array(call.arguments&.arguments)
            arguments.size == 1 && arguments.first.is_a?(Prism::DefNode) ? arguments.first : nil
          end

          def inline_visibility(name, definition)
            return :private unless def_stream(definition)

            MARKERS.include?(name) ? name.to_sym : CLASS_MARKERS.fetch(name, :public)
          end

          def visible?(node)
            stream = def_stream(node)
            return false unless stream

            (@named[stream][node.name.to_s] || @default[stream]) == :public
          end

          # No receiver means this scope's own stream. `def self.x` is always
          # singleton. `def other.x` defines a method on something else, so it
          # is not part of this class's surface.
          def def_stream(node)
            return @own_stream if node.receiver.nil?
            return :singleton if node.receiver.is_a?(Prism::SelfNode)

            nil
          end

          # `class << SomethingElse` reopens another object, not this one.
          def own_singleton_class?(node)
            node.is_a?(Prism::SingletonClassNode) && node.expression.is_a?(Prism::SelfNode)
          end

          def nested_singleton(node)
            self.class.new(self.class.statements(node.body), singleton_scope: true).count
          end

          def symbol_arguments(call)
            Array(call.arguments&.arguments).filter_map do |argument|
              argument.unescaped.to_s if argument.is_a?(Prism::SymbolNode) || argument.is_a?(Prism::StringNode)
            end
          end
        end
      end
    end
  end
end
