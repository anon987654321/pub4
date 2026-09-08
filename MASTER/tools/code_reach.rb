# frozen_string_literal: true

# Which files in lib/ does nothing reach?
#
# data_reach asks it of a declaration, rule_reach of a rule, autofix_reach of a
# transform. This asks it of a file: under Zeitwerk a file is loaded when its
# constant is named, so a constant nothing names is a file nothing runs, and
# `lib/` grows by it without anything failing.
#
#   ruby MASTER/tools/code_reach.rb            # list unreached files
#   ruby MASTER/tools/code_reach.rb --ratchet  # record a new low
#
# The ceiling is 0 and the row exists to keep it there. It is at 0 today, which
# is the answer to a question worth having asked: spine.lib_body_ceiling is
# hundreds of lines over its budget, and none of that can be paid by deletion.
#
# Two traps, both of which this census was written wrong with first, and both of
# which are the same trap the rest of this repo keeps paying for:
#
#   1. The corpus is every TRACKED file, with no extension filter. A whitelist
#      of .rb/.yml/.md cannot see `bin/cli` or the Rakefile, and that is exactly
#      where two "unreached" files turned out to be named.
#   2. The lookbehind is (?<![A-Za-z0-9_]) and must NOT exclude ":". Callers
#      write `Ground::BootChecks`, so excluding ":" hides every qualified use
#      and reports the whole tree as dead. TODO.md already records this shape
#      twice — once for `\b` after a `?` predicate, once for a lookbehind that
#      excluded ".". This is the third.
#
# A file may also be reached by path, through `require` or a manifest, so both
# the constant and the path stem count as a reference.

require "yaml"
require "prism"

module Pub4
  module CodeReach
    MASTER_DIR = File.expand_path("..", __dir__)
    ROOT = File.expand_path("..", MASTER_DIR)
    CEILING = File.join(MASTER_DIR, "data", "code_reach.yml")

    module_function

    def tracked
      @tracked ||= Dir.chdir(ROOT) { `git ls-files`.lines.map(&:chomp) }
                      .map { |rel| File.join(ROOT, rel) }
                      .select { |path| File.file?(path) }
    end

    def bodies
      @bodies ||= tracked.to_h do |path|
        [path, (File.binread(path) rescue "").force_encoding("UTF-8").scrub("?")]
      end
    end

    def lib_files = Dir.glob(File.join(MASTER_DIR, "lib/**/*.rb")).sort

    # The deepest constant the file declares — the one Zeitwerk maps its path to.
    def declared_constant(path)
      result = Prism.parse_file(path)
      return nil unless result.success?

      deepest = nil
      walk = lambda do |node, stack|
        return unless node.respond_to?(:child_nodes)

        name = node.is_a?(Prism::ModuleNode) || node.is_a?(Prism::ClassNode) ? node.constant_path.slice : nil
        here = name ? stack + [name] : stack
        deepest = here if name && (deepest.nil? || here.length > deepest.length)
        node.child_nodes.compact.each { |child| walk.call(child, here) }
      end
      walk.call(result.value, [])
      deepest&.last
    end

    def reached?(path, const)
      base = File.basename(path, ".rb")
      stem = path.sub("#{MASTER_DIR}/lib/", "").sub(/\.rb\z/, "")
      pattern = /(?<![A-Za-z0-9_])#{Regexp.escape(const)}(?![A-Za-z0-9_])/

      bodies.any? do |file, body|
        next false if file == path

        body.include?(stem) || body.include?(base) || body.match?(pattern)
      end
    end

    def unreached
      lib_files.filter_map do |path|
        const = declared_constant(path) or next
        next if reached?(path, const)

        path.sub("#{MASTER_DIR}/", "")
      end
    end

    def recorded
      return {} unless File.exist?(CEILING)

      YAML.safe_load_file(CEILING) || {}
    end

    def ceiling = recorded.fetch("unreached", 0)

    def recorded_members = Array(recorded["members"])

    def run(ratchet: false)
      out = unreached
      puts "code_reach: #{out.size} lib files nothing names (ceiling #{ceiling})"

      if ratchet && out.size <= ceiling
        File.write(CEILING, { "unreached" => out.size, "members" => out.sort }.to_yaml)
        verb = out.size < ceiling ? "recorded #{out.size} as the new low" : "re-recorded #{out.size}"
        puts "code_reach: #{verb}, with its members"
        return 0
      end
      return 0 unless out.size > ceiling

      arrived = out - recorded_members
      puts "code_reach: #{arrived.size} arrived since the low was recorded:"
      arrived.each { |file| puts "  + #{file}" }
      out.each { |file| puts "  #{file} — no constant and no path names this file; wire it or delete it" }
      1
    end
  end
end

exit Pub4::CodeReach.run(ratchet: ARGV.include?("--ratchet")) if $PROGRAM_NAME == __FILE__
