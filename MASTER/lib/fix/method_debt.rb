# frozen_string_literal: true

require "prism"

module Master
  module Fix

    # A finding reported on a `def` line speaks for the whole method: ABC_SIZE,
    # CYCLOMATIC_COMPLEXITY, RuboCop's Metrics cops and reek's method smells all
    # land there. Judged by that line alone, a change that only touched a signature
    # inherited the method's standing debt, and a change deep inside the body that
    # made the method worse escaped. So a def-line finding is the change's when the
    # change touches the method's lines and the method is worse than at the base.
    class MethodDebt

      # Worse means the finding is new there or its figure grew: the file-size
      # laws' `grew?` asked of one method. A method is matched to its base by its
      # qualified name (Outer::Inner#name, .name for a singleton), so lines moving
      # above it do not matter, and a rename is a new method. Two findings are the
      # same when their laws match and their messages match with the method's name
      # taken out and every number masked. The figure is the measured number: the N
      # of an "N/limit" pair when there is one (RuboCop's "[27.39/17]"), otherwise
      # the first number (ABC_SIZE's size, the complexity, reek's count).
      Method = Data.define(:key, :name, :range)

      Sighting = Data.define(:key, :law, :shape, :figure)

      NUMBER = /\d+(?:\.\d+)?/
      MEASURE_OF_LIMIT = %r{(\d+(?:\.\d+)?)\s*/\s*\d+(?:\.\d+)?}

      # The methods of a Ruby source keyed by the line their `def` opens on; none
      # for a source Prism cannot parse.
      def self.methods_by_line(source)
        result = Prism.parse(source.to_s)
        return {} if result.failure?

        methods = {}
        collect(result.value, [], methods)
        methods
      end

      def self.collect(node, nesting, methods)
        case node
        when Prism::ClassNode, Prism::ModuleNode
          nesting = [*nesting, node.constant_path.slice]
        when Prism::DefNode
          methods[node.location.start_line] ||= method_of(node, nesting)
        end
        node.compact_child_nodes.each { |child| collect(child, nesting, methods) }
      end

      def self.method_of(node, nesting)
        separator = node.receiver ? "." : "#"
        range = node.location.start_line..node.location.end_line
        Method.new(key: "#{nesting.join("::")}#{separator}#{node.name}", name: node.name.to_s, range:)
      end
      private_class_method :collect, :method_of

      # +base_findings+ are the scanner's findings on +base_source+, the version
      # the change is measured against.
      def initialize(source:, base_source:, base_findings:)
        @methods = self.class.methods_by_line(source)
        base_methods = self.class.methods_by_line(base_source)

        @base = Array(base_findings).filter_map do |finding|
          method = base_methods[line_of(finding)]
          sighting(finding, method) if method
        end
      end

      # The method whose `def` line +finding+ sits on, or nil for any other line.
      def method_at(finding) = @methods[line_of(finding)]

      # True when +finding+, a def-line finding, is absent at the base or measures
      # more than it did there.
      def worse?(finding)
        method = method_at(finding)
        return true unless method

        own = sighting(finding, method)
        before = @base.select { |base| base.with(figure: nil) == own.with(figure: nil) }
        return true if before.empty?
        return false if own.figure.nil?

        before.all? { |base| base.figure.nil? || own.figure > base.figure }
      end

      private

      def line_of(finding) = (finding[:line] || finding["line"]).to_i

      def sighting(finding, method)
        text = (finding[:message] || finding["message"]).to_s
        text = text.gsub(/(?<!\w)#{Regexp.escape(method.name)}(?![\w?!=])/, "")
        figure = text[MEASURE_OF_LIMIT, 1] || text[NUMBER]

        Sighting.new(key: method.key, law: (finding[:law] || finding["law"]).to_s,
                     shape: text.gsub(NUMBER, "#"), figure: figure&.to_f)
      end
    end
  end
end
