# frozen_string_literal: true

# Which methods in MASTER/lib are unreachable from anything outside it?
#
# method_reach.rb answers one layer: a method no line names. That is the first
# cut, and acting on it alone over-deletes in one direction and under-deletes in
# the other. Deleting a dead handler orphans the helpers only it called, so the
# census has to be re-run until it settles — and a helper called only by another
# dead method never appears in the first pass at all.
#
#   ruby MASTER/tools/method_graph.rb
#
# This is the closure. Every method is a node; every identifier in its body is
# an edge. The roots are the names something outside `lib/` uses — bin/, test/,
# spec/, tools/, the Rakefile, the other three trees — plus the names `lib/`
# uses at file scope, where a registration lives. Anything the roots cannot
# reach is unreachable no matter how many layers deep it sits.
#
# Name-based, not receiver-based, and deliberately so: two classes with a `call`
# each collapse into one node, which can only make the answer more conservative.
# A name this reports as unreachable is unreachable under every receiver.
#
# The four traps method_reach.rb documents all apply here and are carried over
# unchanged: send-prefix dispatch, a name inside a log string, an endless
# method's body on the def line, and substring matching. Read that file first.

require "prism"
require "set"

module Operator
  module MethodGraph
    ROOT = File.expand_path("../..", __dir__)
    MASTER = File.expand_path("..", __dir__)
    LIB = File.join(MASTER, "lib")
    IDENTIFIER = /[a-z_][A-Za-z0-9_]*[?!]?/

    # Names Ruby or a framework calls for you. No graph edge can exist for any of
    # them, so each one arrives in the unreachable list on its own, and deleting
    # it deletes behaviour that nothing in the tree appears to ask for.
    #
    # Three of these were found by reading the list rather than by writing it:
    # const_missing (Ruby calls it on a missing constant, and the tree's only
    # other mention is a scan rule's regex), deconstruct_keys (the hook `case ...
    # in {ok:}` calls, which Result defines twice and nothing names), and _dump
    # (Marshal's). The lesson is the shape: a hook is invisible to a call-site
    # census by definition, so this list is the census's blind spot written down.
    FRAMEWORK = %w[
      initialize to_s inspect call each each_pair each_entry to_h to_a to_ary
      to_str to_int to_io to_proc to_f to_i hash eql? == <=> succ coerce
      method_missing respond_to_missing? const_missing deconstruct
      deconstruct_keys marshal_dump marshal_load _dump _load pretty_print
      inherited included extended prepended new run start stop setup teardown
      before after
    ].freeze

    # A setter is written `thing.name = value` and an index `thing[key]`, so the
    # identifier scan sees `name` and nothing at all. Neither can ever be reached
    # by name, which would report every one of them as dead — `model=`, `[]` and
    # `[]=` were in the first list for exactly that reason.
    UNCALLABLE_BY_NAME = /[=\[]/

    module_function

    def tracked
      Dir.chdir(ROOT) { `git ls-files`.lines.map(&:chomp).uniq }
         .map { |rel| File.join(ROOT, rel) }
         .select { |path| File.file?(path) }
    end

    # Comments and prose string literals dropped. Two things are kept: a short
    # lowercase literal, because that is how a symbol table names a handler, and
    # whatever sits inside an interpolation, because that is code. Blanking the
    # whole literal blanked `"…#{role_description}…"`, which is the only call
    # four swarm workers' role_description has.
    def code_only(line)
      return "" if line.match?(/\A\s*#/)

      line.sub(/\s#(?!\{).*\z/, "").gsub(/"[^"]*"|'[^']*'/) do |literal|
        next literal if literal.match?(/\A["'][a-z_]+["']\z/)

        literal.scan(/#\{([^}]*)\}/).flatten.join(" ")
      end
    end

    def names_in(text) = text.scan(IDENTIFIER)

    # Every def in lib/, with the line span of its body, so a caller can be
    # attributed to the method it sits inside rather than to the file.
    def definitions
      Dir.glob(File.join(LIB, "**", "*.rb")).sort.flat_map do |path|
        parsed = Prism.parse_file(path)
        next [] unless parsed.success?

        found = []
        walk = lambda do |node|
          next unless node.respond_to?(:child_nodes)

          if node.is_a?(Prism::DefNode)
            found << { file: path, name: node.name.to_s,
                       first: node.location.start_line, last: node.location.end_line }
          end
          node.child_nodes.compact.each { |child| walk.call(child) }
        end
        walk.call(parsed.value)
        found
      end
    end

    # Roots, dynamic-dispatch prefixes and Prism::Visitor hooks, in one pass over
    # every tracked file. A name used anywhere outside lib/ is a root; inside
    # lib/, only a use at file scope is, because a use inside a method is an edge.
    def survey(defs_by_file)
      roots = Set.new
      prefixes = Set.new
      visitors = Set.new

      tracked.each do |path|
        inside_lib = path.start_with?("#{LIB}/")
        spans = inside_lib ? defs_by_file.fetch(path, []) : []
        visitor_file = false
        File.foreach(path).with_index(1) do |raw, number|
          line = raw.dup.force_encoding("UTF-8").scrub("?")
          visitor_file ||= line.include?("Prism::Visitor")
          line.scan(/(?:send|public_send)\(\s*["':]([a-z_]+)_#\{/) { prefixes << Regexp.last_match(1) }
          if (match = line.match(/^\s*def\s+(?:self\.)?(#{IDENTIFIER})/))
            visitors << match[1] if visitor_file && match[1].start_with?("visit_")
            # An endless method's body is on the def line, so its calls are read
            # from what follows the `=` rather than lost with the line.
            tail = line.split(/\)\s*=\s*|\A\s*def\s+\S+\s*=\s*/, 2)[1]
            names_in(code_only(tail.to_s)).each { |name| roots << name } unless inside_lib
            next
          end
          next if inside_lib && spans.any? { |span| number > span[:first] && number <= span[:last] }

          names_in(code_only(line)).each { |name| roots << name }
        end
      rescue StandardError
        next
      end
      [roots, prefixes, visitors]
    end

    # One node per method name, holding every name its bodies call.
    def edges(defs)
      graph = Hash.new { |hash, key| hash[key] = Set.new }
      defs.group_by { |definition| definition[:file] }.each do |path, group|
        lines = File.readlines(path, encoding: "UTF-8")
        group.each do |definition|
          body = lines[(definition[:first] - 1)...definition[:last]].to_a.join
          graph[definition[:name]].merge(names_in(code_only(body)))
        end
      rescue StandardError
        next
      end
      graph
    end

    def unreachable
      defs = definitions
      defs_by_file = defs.group_by { |definition| definition[:file] }
      roots, prefixes, visitors = survey(defs_by_file)

      seeds = roots.dup
      seeds.merge(FRAMEWORK)
      seeds.merge(visitors)
      defined_names = defs.map { |definition| definition[:name] }.to_set
      seeds.merge(defined_names.select { |name| prefixes.any? { |prefix| name.start_with?("#{prefix}_") } })

      graph = edges(defs)
      reached = Set.new
      queue = seeds.to_a
      until queue.empty?
        name = queue.pop
        next unless reached.add?(name)

        graph[name].each { |callee| queue << callee unless reached.include?(callee) }
      end

      dead = defs.reject do |definition|
        reached.include?(definition[:name]) || definition[:name].match?(UNCALLABLE_BY_NAME)
      end
      [dead, defs.size, prefixes, visitors]
    end

    def report
      dead, total, prefixes, visitors = unreachable
      puts "send-prefix dispatch: #{prefixes.to_a.sort.join(', ')}"
      puts "Prism::Visitor hooks: #{visitors.size}"
      puts "definitions in MASTER/lib: #{total}"
      puts "unreachable from every root: #{dead.size}, #{dead.sum { |d| d[:last] - d[:first] }} body lines"
      puts
      dead.group_by { |definition| definition[:file] }
          .sort_by { |_, group| -group.sum { |d| d[:last] - d[:first] } }
          .each do |path, group|
        rel = path.sub("#{ROOT}/", "")
        lines = group.sum { |d| d[:last] - d[:first] }
        puts "  #{rel}  #{group.size}, #{lines} lines: #{group.map { |d| d[:name] }.sort.join(', ')}"
      end
    end
  end
end

Operator::MethodGraph.report if $PROGRAM_NAME == __FILE__
