# frozen_string_literal: true

# Renames a constant across the repo, and finds the ones worth renaming.
#
# MASTER reads every line of this tree against 242 rules and cannot rename a
# thing. Four rules touch names and all four are `autofix: false`, because a
# constant rename is a file move under Zeitwerk and nothing here could perform
# one safely. So `ZSH_BANNED` — the tools banned INSIDE a zsh command, bash among
# them — sat in lib/io/shell.rb reading as its own opposite until a person
# noticed, and `Master::MasterData` stuttered in the boot path for months.
#
#   ruby MASTER/tools/rename.rb                       # what deserves a rename
#   ruby MASTER/tools/rename.rb Old New               # what that rename touches
#   ruby MASTER/tools/rename.rb Old New --apply       # do it
#
# Proposals, not autofix, and the line is where the judgement is. This tool can
# prove a name is free and that a rewrite reached every reference; it cannot
# prove a name is better, and a rename that lands in a commit nobody chose is a
# worse defect than the name it fixed. `--apply` is one word away.
#
# Two traps this repo paid for on 2026-09-11, both handled below. A constant is
# also a path: renaming Pub4::StatusReport without moving lib/pub4 leaves
# Zeitwerk expecting a file that moved, and `File.join(LIB, "pub4",
# "status_report.rb")` in a test is a reference no constant scan can see. And a
# word boundary is the whole safety of the rewrite: `Pub4` glued to `Openbsd` is
# a different constant, and \b is what keeps the sweep off it.

require "json"
require "prism"

module Operator
  module Rename
    # The tree this reads. test/test_rename.rb points it at a planted repository,
    # because a renamer proved only against the tree it lives in is proved once:
    # the fixture holds the shapes that are rare here — a constant glued to
    # another word, a path written as a string. Nothing else sets it.
    ROOT = ENV.fetch("RENAME_ROOT", File.expand_path("../..", __dir__))
    TREES = ENV["RENAME_ROOT"] ? ["."] : %w[MASTER OPENBSD RAILS STUDIO].freeze
    SKIP = %r{/(vendor|node_modules|tmp|log|knowledge|output|\.master|\.git)/}
    TEXT_EXTENSIONS = %w[.rb .rake .erb .yml .yaml .md .js .json .txt .scss .css].freeze

    # A category is what a thing IS to a framework, never what it does here.
    # Helper and Service stay off this list: both are Rails' own vocabulary, and
    # app/helpers is a directory Rails resolves by name.
    CATEGORY_SUFFIXES = %w[Manager Handler Processor Wrapper Utility Utilities Util Utils Info Data Misc Stuff].freeze

    Candidate = Struct.new(:constant, :file, :line, :proposal, :reason, keyword_init: true)

    module_function

    def files
      @files ||= TREES.flat_map { |tree| Dir.glob(File.join(ROOT, tree, "**", "*")) }
                      .reject { |path| path =~ SKIP }
                      .select { |path| File.file?(path) && TEXT_EXTENSIONS.include?(File.extname(path)) }
                      .sort
    end

    def ruby_files = files.select { |path| File.extname(path) == ".rb" }

    # Every class or module definition, with the namespace it sits in.
    def definitions
      @definitions ||= read_definitions
    end

    # Parsed, not read by indentation. A regex over lines counts `class
    # DemoThingManager` inside a heredoc — this file's own test fixture — as a
    # definition, and a census that reports its own fixture teaches the reader to
    # skim it. Prism knows the difference between code and a string that looks
    # like code.
    def read_definitions
      ruby_files.flat_map do |path|
        source = File.read(path)
        result = Prism.parse(source)
        next [] unless result.success?

        collect(result.value, [], path)
      rescue StandardError => e
        # A file that does not parse has names this cannot count, and saying so
        # is the difference between a census with a hole and a census that lies.
        warn "rename: #{path} did not parse (#{e.class}) — its names go uncounted"
        []
      end
    end

    def collect(node, namespace, path)
      return [] unless node.respond_to?(:child_nodes)

      node.child_nodes.compact.flat_map do |child|
        case child
        when Prism::ClassNode, Prism::ModuleNode
          parts = child.constant_path.slice.split("::")
          own = { constant: parts.last, namespace: namespace + parts[0..-2],
                  file: path, line: child.location.start_line }
          [own] + collect(child, namespace + parts, path)
        else
          collect(child, namespace, path)
        end
      end
    end

    # One row per name, not per definition. A class reopened across fourteen
    # files is one rename, and a report that lists it fourteen times buries the
    # thirty others under it — which is how a list stops being read.
    def candidates
      found = definitions.filter_map { |definition| category_suffix(definition) || stutter(definition) }
      by_name = found.group_by { |row| [row.constant, File.dirname(row.file)] }
      one_each = by_name.map { |_, rows| rows.min_by(&:file) }
      one_each.sort_by { |row| [row.proposal ? 0 : 1, row.file] }
    end

    # A name whose last word says which drawer it lives in rather than what it
    # holds. The proposal drops the suffix, which is the rename somebody made by
    # hand for ProviderQuarantineManager and is the only mechanical one available:
    # what the thing actually does is not in the old name to be read out.
    def category_suffix(definition)
      name = definition[:constant]
      suffix = CATEGORY_SUFFIXES.find { |candidate| name.end_with?(candidate) && name != candidate }
      return unless suffix

      proposal = name.delete_suffix(suffix)
      return if proposal.empty? || proposal !~ /[A-Z]/

      Candidate.new(constant: name, file: definition[:file], line: definition[:line],
                    proposal: free?(proposal, definition) ? proposal : nil,
                    reason: "#{suffix} is a category, not a subject")
    end

    # Master::MasterData. The namespace already says Master, so the child says it
    # twice and the reader has to hold a word that carries nothing.
    def stutter(definition)
      parent = definition[:namespace].last
      name = definition[:constant]
      return unless parent && name != parent && name.start_with?(parent)

      proposal = name.delete_prefix(parent)
      return if proposal.empty? || proposal !~ /\A[A-Z]/

      Candidate.new(constant: name, file: definition[:file], line: definition[:line],
                    proposal: free?(proposal, definition) ? proposal : nil,
                    reason: "#{parent} is already the namespace")
    end

    # Free means free of everything that resolves: a sibling in the tree, and
    # Ruby's own constants. Master::MasterData shortens to Data, which is a core
    # class since 3.2 — a proposal that collides is worse than none, so it is
    # withheld rather than offered with a warning nobody reads.
    def free?(proposal, definition)
      return false if Object.const_defined?(proposal.to_sym)

      siblings = definitions.select { |other| other[:namespace] == definition[:namespace] }
      siblings.none? { |other| other[:constant] == proposal }
    end

    # Every reference to the constant, and every reference to the file that
    # carries it. The second half is the one a constant scan misses: a require, a
    # File.join segment, a Zeitwerk ignore entry in data/autoload.yml.
    def references(constant, basename: nil)
      word = /\b#{Regexp.escape(constant)}\b/
      path_forms = basename ? [%("#{basename}"), %('#{basename}'), "/#{basename}", "#{basename}.rb"] : []

      files.filter_map do |path|
        text = File.read(path)
        lines = text.each_line.with_index(1).select do |line, _|
          line.match?(word) || path_forms.any? { |form| line.include?(form) }
        end
        next if lines.empty?

        { file: path, lines: lines.map { |line, number| "#{number}: #{line.chomp}" } }
      end
    end

    def snake(constant)
      constant.gsub(/([a-z0-9])([A-Z])/, '\1_\2').gsub(/([A-Z]+)([A-Z][a-z])/, '\1_\2').downcase
    end

    def defining_file(constant)
      definitions.find { |definition| definition[:constant] == constant }&.fetch(:file)
    end

    # The rename itself. A file whose basename is the constant's own name moves
    # with it, because under Zeitwerk the path IS the name and a constant that
    # stays where it was is a constant that stops loading.
    def apply!(old_name, new_name)
      moved = move_file(old_name, new_name)
      touched = rewrite(old_name, new_name, moved)
      { moved:, files: touched }
    end

    def move_file(old_name, new_name)
      path = defining_file(old_name)
      return unless path && File.basename(path, ".rb") == snake(old_name)

      target = File.join(File.dirname(path), "#{snake(new_name)}.rb")
      system("git", "-C", ROOT, "mv", path, target) || raise("git mv failed: #{path}")
      @files = nil
      [path.sub("#{ROOT}/", ""), target.sub("#{ROOT}/", "")]
    end

    def rewrite(old_name, new_name, moved)
      word = /\b#{Regexp.escape(old_name)}\b/
      old_base = moved && File.basename(moved[0], ".rb")
      new_base = moved && File.basename(moved[1], ".rb")

      files.filter_map do |path|
        original = File.read(path)
        text = original.gsub(word, new_name)
        if old_base
          text = text.gsub(%("#{old_base}"), %("#{new_base}"))
                     .gsub(%('#{old_base}'), %('#{new_base}'))
                     .gsub("/#{old_base}\"", "/#{new_base}\"")
                     .gsub("#{old_base}.rb", "#{new_base}.rb")
        end
        next if text == original

        File.write(path, text)
        path.sub("#{ROOT}/", "")
      end
    end

    def report_candidates
      rows = candidates
      named = rows.count(&:proposal)
      puts "rename: #{rows.size} name(s) carry a category or a stutter, #{named} with a free shorter name"
      rows.sort_by(&:file).each do |row|
        target = row.proposal ? "-> #{row.proposal}" : "(no free name — say what it does)"
        puts "  #{row.file.sub("#{ROOT}/", "")}:#{row.line}  #{row.constant} #{target}"
        puts "      #{row.reason}"
      end
      rows.empty? ? 0 : 1
    end

    # A rewrite this wide has to arrive as its own diff. Mixed into somebody
    # else's uncommitted work it cannot be reviewed, reverted, or told apart
    # from it — and this checkout is shared, which is the first trap CLAUDE.md
    # names. The guard also bounds a mistake: the first run of test_rename.rb
    # lost its environment on the way to the child process and aimed the tool at
    # the real repository, where a dirty tree would have stopped it.
    def dirty
      `git -C #{ROOT} status --porcelain`.lines.map(&:chomp).reject(&:empty?)
    end

    def report_plan(old_name, new_name, apply:)
      path = defining_file(old_name)
      abort "rename: nothing defines #{old_name}" unless path
      abort "rename: #{old_name} and #{new_name} are the same name" if old_name == new_name
      abort "rename: #{new_name} already resolves" if Object.const_defined?(new_name.to_sym) && !apply

      if apply && dirty.any?
        warn "rename: #{dirty.size} uncommitted change(s) — commit or stash them first:"
        dirty.first(10).each { |line| warn "  #{line}" }
        abort "rename: refusing to mix a repo-wide rewrite into an existing diff"
      end

      hits = references(old_name, basename: File.basename(path, ".rb"))
      puts "rename: #{old_name} -> #{new_name}, defined at #{path.sub("#{ROOT}/", "")}"
      puts "rename: #{hits.sum { |hit| hit[:lines].size }} line(s) in #{hits.size} file(s)"
      unless apply
        hits.first(20).each { |hit| puts "  #{hit[:file].sub("#{ROOT}/", "")} (#{hit[:lines].size})" }
        puts "rename: nothing written — add --apply"
        return 0
      end

      result = apply!(old_name, new_name)
      puts "rename: moved #{result[:moved].join(' -> ')}" if result[:moved]
      puts "rename: rewrote #{result[:files].size} file(s)"
      puts "rename: run the suite — a rewrite that parses is not a rewrite that works"
      0
    end
  end
end

if $PROGRAM_NAME == __FILE__
  args = ARGV.reject { |arg| arg.start_with?("--") }
  apply = ARGV.include?("--apply")
  exit(args.size >= 2 ? Operator::Rename.report_plan(args[0], args[1], apply:) : Operator::Rename.report_candidates)
end
