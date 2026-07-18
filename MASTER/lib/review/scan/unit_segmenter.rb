# frozen_string_literal: true

require "prism"

module Master
  module Review
    module Scan
    # Slices a source file into logical units for detect_unit scanning axis.
    # Ruby: method/class/module nodes via Prism AST.
    # Other languages: paragraph-based line grouping (blank-line delimited).
      class UnitSegmenter
        Unit = Struct.new(:name, :type, :start_line, :end_line, :source, keyword_init: true)

        def self.segment(path, source)
          new(path, source).segment
        end

        def initialize(path, source)
          @path = path
          @source = source
          @lines = source.lines
        end

        def segment
          ruby? ? ruby_units : prose_units
        end

        private

        def ruby_units
          result = Prism.parse(@source)
          return prose_units unless result.success?
          units = []
          walk(result.value, units)
          units.empty? ? prose_units : units
        end

        def walk(node, units)
          return unless node.is_a?(Prism::Node)
          case node
          when Prism::DefNode
            units << build_unit(node:, name: node.name.to_s, type: :method)
          when Prism::ClassNode
            units << build_unit(node:, name: node.constant_path.slice, type: :class)
            node.child_nodes.compact.each { |c| walk(c, units) }
            return
          when Prism::ModuleNode
            units << build_unit(node:, name: node.constant_path.slice, type: :module)
            node.child_nodes.compact.each { |c| walk(c, units) }
            return
          end
          node.child_nodes.compact.each { |c| walk(c, units) }
        end

        def build_unit(node:, name:, type:)
          s = node.location.start_line
          e = node.location.end_line
          Unit.new(
            name: name,
            type: type,
            start_line: s,
            end_line: e,
            source: @lines[(s - 1)..(e - 1)].join
          )
        end

        # Blank-line delimited paragraph units — works for prose, YAML, config, HTML.
        def prose_units
          units = []
          buffer = []
          start = 1
          @lines.each_with_index do |line, idx|
            lineno = idx + 1
            if line.strip.empty?
              flush_paragraph!(units, buffer, start, lineno - 1)
              buffer = []
              start = lineno + 1
            else
              buffer << line
            end
          end
          flush_paragraph!(units, buffer, start, @lines.size)
          units
        end

        def flush_paragraph!(units, buffer, start_line, end_line)
          return unless buffer.any?(&method(:non_blank?))

          units << Unit.new(name: "paragraph_#{units.size + 1}", type: :paragraph,
                            start_line:, end_line:, source: buffer.join)
        end

        def non_blank?(line) = !line.strip.empty?

        def ruby? = File.extname(@path).downcase == ".rb"
      end
    end
  end
end
