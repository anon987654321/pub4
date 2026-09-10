# frozen_string_literal: true

# Which methods in MASTER/lib does nothing name?
#
# code_reach.rb asks this of a file and answers 0. This asks it of a method,
# which is SPRAWL-104: handlers left behind when a surface closed, helpers whose
# only caller went, commands nothing registers.
#
#   ruby MASTER/tools/method_reach.rb
#
# A name here is a candidate, not a corpse. Verify each with a word-boundary
# grep across all four trees before deleting, and delete the transitive closure
# rather than one layer — removing a dead handler orphans the helpers only it
# called, so this has to be re-run until it settles.
#
# Four traps, and the first pass of this census fell into all four.
#
#   1. Dynamic dispatch. `send` with an interpolated prefix reaches nine methods
#      with no literal call site, and Prism::Visitor calls every visit_ hook for
#      you. The prefixes are harvested from the corpus rather than listed, so a
#      new one cannot go unnoticed.
#   2. A name inside a string is not a call. run_swallow_report read as reached
#      because its own rescue logs "CLI.run_swallow_report". Comments and prose
#      literals are dropped — but a short lowercase literal is kept, because that
#      is how a symbol table names a handler, and it is the only thing reaching
#      run_snapshot from heartbeat.rb.
#   3. An endless method carries its body on the def line. Skipping the whole
#      line lost every call it made, and undo_line read as dead when its only
#      caller is `def dispatch_undo(...) = undo_line(...)`. Sixteen of them.
#   4. Substring matching. A grep for `dispatch_core` matches
#      `dispatch_core_slash_command`, a different method — the same prefix trap
#      code_reach.rb records for its lookbehind.
#
# One streaming pass, no corpus in memory. The shape that read every tracked
# body into a hash and scanned it once per candidate ran the machine out of
# memory before it ran out of candidates.

require "prism"
require "set"

# The checkout this file sits in, not the one it was written in. A hardcoded
# /Users/mac/Documents/GitHub/pub4 measured the main tree from inside every
# worktree, so a census run against a branch reported the branch it was not on.
ROOT = File.expand_path("../..", __dir__)
MASTER = File.join(ROOT, "MASTER")
IDENTIFIER = /[a-z_][A-Za-z0-9_]*[?!]?/

FRAMEWORK = %w[
  initialize to_s inspect call each each_pair to_h to_a to_proc hash eql? ==
  <=> coerce method_missing respond_to_missing? inherited included extended
  prepended new run start stop setup teardown before after
].freeze

# Comments and prose string literals dropped. Two things are kept: a short
# lowercase literal, because that is how a symbol table names a handler, and
# whatever sits inside an interpolation, because that is code.
def code_only(line)
  return "" if line.match?(/\A\s*#/)

  line.sub(/\s#(?!\{).*\z/, "").gsub(/"[^"]*"|'[^']*'/) do |literal|
    next literal if literal.match?(/\A["'][a-z_]+["']\z/)

    literal.scan(/#\{([^}]*)\}/).flatten.join(" ")
  end
end

uses = Hash.new(0)
defs = Hash.new(0)
prefixes = Set.new
visitors = Set.new

# uniq: ls-files prints an unmerged path once per stage.
Dir.chdir(ROOT) { `git ls-files`.lines.map(&:chomp).uniq }.each do |rel|
  path = File.join(ROOT, rel)
  next unless File.file?(path)

  visitor_file = false
  File.foreach(path) do |raw|
    line = (raw.dup.force_encoding("UTF-8").scrub("?") rescue next)
    visitor_file ||= line.include?("Prism::Visitor")
    line.scan(/(?:send|public_send)\(\s*["':]([a-z_]+)_#\{/) { prefixes << Regexp.last_match(1) }
    if (match = line.match(/^\s*def\s+(?:self\.)?(#{IDENTIFIER})/))
      defs[match[1]] += 1
      visitors << match[1] if visitor_file && match[1].start_with?("visit_")
      # An endless method carries its body on the def line, so skipping the
      # whole line loses every call it makes. undo_line read as dead because
      # its only caller is `def dispatch_undo(...) = undo_line(...)`.
      body = line.split(/\)\s*=\s*|\A\s*def\s+\S+\s*=\s*/, 2)[1]
      code_only(body.to_s).scan(IDENTIFIER) { |name| uses[name] += 1 }
      next
    end
    code_only(line).scan(IDENTIFIER) { |name| uses[name] += 1 }
  end
rescue StandardError
  next
end

definitions = Dir.glob(File.join(MASTER, "lib/**/*.rb")).sort.flat_map do |path|
  parsed = Prism.parse_file(path)
  next [] unless parsed.success?

  found = []
  walk = lambda do |node|
    next unless node.respond_to?(:child_nodes)
    if node.is_a?(Prism::DefNode)
      found << [path.sub("#{ROOT}/", ""), node.location.start_line, node.name.to_s,
                node.location.end_line - node.location.start_line]
    end
    node.child_nodes.compact.each { |c| walk.call(c) }
  end
  walk.call(parsed.value)
  found
end

puts "send-prefix dispatch: #{prefixes.to_a.sort.join(', ')}"
puts "Prism::Visitor hooks: #{visitors.size}"
puts "definitions in MASTER/lib: #{definitions.size}"

dead = definitions.reject do |(_f, _l, name, _b)|
  FRAMEWORK.include?(name) || visitors.include?(name) ||
    prefixes.any? { |p| name.start_with?("#{p}_") } || uses[name].positive?
end

puts "named nowhere in code: #{dead.size}, carrying #{dead.sum { |d| d[3] }} body lines"
puts
dead.group_by { |d| d[0] }.sort_by { |_, ds| -ds.sum { |d| d[3] } }.each do |file, ds|
  puts "  #{file}  #{ds.size}, #{ds.sum { |d| d[3] }} lines: #{ds.map { |d| d[2] }.join(', ')}"
end
puts
%w[public_method_count swarm_review run_snapshot run_chitchat dispatch_grep].each do |name|
  puts "control #{name}: #{uses[name]} use(s), #{defs[name]} def(s)"
end
