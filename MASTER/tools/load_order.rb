# frozen_string_literal: true

# An ordered manifest is ordered only while something checks it.
#
# STUDIO/dilla's ENGINE_PARTS lists 77 files whose order is load-bearing:
# constants in them are computed at load time from constants above them, so
# moving a file changes values rather than raising. A merge that relocates one
# file past the definitions it reads is the ordinary way that happens.
#
#   ruby MASTER/tools/load_order.rb STUDIO/dilla
#
# The distinction that matters is load time versus call time. A constant named
# inside a method body resolves when the method runs, so its definition may come
# later; a constant named at a file top level resolves as the file loads, and its
# definition must already exist. Only the second constrains the manifest, and
# only the syntax tree separates them.

require "json"

module Pub4
  module LoadOrder
    module_function

    def manifest(root)
      sources = File.join(root, "lib", "engine_sources.rb")
      return [] unless File.file?(sources)

      File.read(sources)[/ENGINE_PARTS\s*=\s*%w\[(.*?)\]/m, 1].to_s.split(/\s+/).reject(&:empty?)
    end

    def defines(path) = File.read(path).scan(/^([A-Z][A-Z0-9_]*)\s*=/).flatten

    # Load time versus call time is a question about the syntax tree, not about
    # lines: counting `def` without its `end` marks every later line call time, and
    # excluding endless defs by looking for `=` sweeps up every default argument.
    # Prism answers it exactly — a constant read is load time when no DefNode
    # encloses it.
    def reads_at_load(path)
      require "prism"
      found = []
      walk = lambda do |node, in_def|
        return unless node.is_a?(Prism::Node)

        inside = in_def || node.is_a?(Prism::DefNode)
        found << node.name.to_s if node.is_a?(Prism::ConstantReadNode) && !inside
        node.compact_child_nodes.each { |child| walk.call(child, inside) }
      end
      walk.call(Prism.parse_file(path).value, false)
      found
    end

    def violations(root)
      parts = manifest(root)
      owner = {}
      parts.each_with_index do |part, index|
        path = File.join(root, "lib", "engine", "#{part}.rb")
        next unless File.file?(path)

        defines(path).each { |const| owner[const] ||= [part, index] }
      end

      parts.each_with_index.flat_map do |part, index|
        path = File.join(root, "lib", "engine", "#{part}.rb")
        next [] unless File.file?(path)

        reads_at_load(path).uniq.filter_map do |const|
          defined_in, at = owner[const]
          next unless defined_in && at > index

          { file: part, reads: const, defined_in:, needs_index: at, has_index: index }
        end
      end
    end

    def run(root, json: false)
      found = violations(root)
      parts = manifest(root)
      return puts(JSON.pretty_generate(manifest: parts.size, violations: found)) if json

      puts "load_order: #{parts.size} manifest entries, #{found.size} read-before-defined"
      found.each do |v|
        puts "  #{v[:file]} (#{v[:has_index]}) reads #{v[:reads]} at load time, defined by #{v[:defined_in]} (#{v[:needs_index]})"
      end
      puts(found.empty? ? "load_order: every load-time constant is defined above its reader" : "load_order: the manifest order is wrong")
      found.empty? ? 0 : 1
    end
  end
end

if $PROGRAM_NAME == __FILE__
  target = ARGV.reject { |a| a.start_with?("--") }.first
  abort "usage: load_order.rb [--json] <tree-with-engine_sources>" unless target
  exit Pub4::LoadOrder.run(target, json: ARGV.include?("--json"))
end
