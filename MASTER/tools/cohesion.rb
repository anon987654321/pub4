# frozen_string_literal: true

# Files that are one concept wearing several names.
#
# Every structural rule in data/rules.yml points one way: SMALL_FILES,
# NO_GOD_CLASS and INTEGRATED_SYSTEMS all say "split further". None says "these
# three are one thing", so no scan proposes a merge, and one concept spread over
# three files that reference each other in both directions stays that way.
#
#   ruby MASTER/tools/cohesion.rb STUDIO/dilla/lib/engine
#   ruby MASTER/tools/cohesion.rb --json RAILS/shared/lib
#
# It emits a plan rather than a patch. Moving code between files is not a
# line-level edit and MASTER's autofix transforms are all line-level; a merge
# also has to respect load order, which is a property of the tree and not of any
# file. So this states what to do, in what order, and what to check — and a
# person or a model does the surgery.
#
# Two plan kinds, because two tree shapes need opposite surgery.
#
# MERGE, for files with no namespace of their own: dilla's engine defines its
# methods on Object, so render_seed.rb and render_techno.rb genuinely can become
# one render.rb. Gated on bidirectional reference, which is what separates a
# family from a prefix that merely reads alike.
#
# REGROUP, for files that each declare their own constant: under Zeitwerk a file
# path *is* a constant name, so Ground::SandboxPolicy and Ground::SubagentPolicy
# cannot be merged into one policy.rb — the loader would refuse it. What they
# want is a shelf: lib/ground/policy/sandbox.rb defining Ground::Policy::Sandbox.
# The signal is different too. A merge needs proof the files are one concept; a
# regroup only needs a drawer with five things of one kind in it, because the
# gain is navigational rather than structural.
#
# Both prefix and suffix families, because trees name families both ways and
# grouping on `split("_").first` alone saw only one of them. dilla writes
# render_seed / render_techno; MASTER writes sandbox_policy / workflow_policy.
# Reading only prefixes made this tool structurally blind to MASTER's own shape:
# it reported "nothing to merge" for lib/ground, lib/review, lib/cli and
# lib/voice — 325 files — and the reason was the matcher, not the tree.

require "json"
require "yaml"

module Pub4
  module Cohesion
    MIN_FAMILY = 3

    module_function

    # Families keyed both ways. A file joins at most one family per kind, and a
    # single-word name (policy.rb, memory.rb) is its own prefix and suffix, so it
    # joins the family it names — which is usually the right merge site.
    def families(dir)
      paths = Dir.glob(File.join(dir, "*.rb"))
      %i[prefix suffix].flat_map do |kind|
        paths.group_by { |path| family_key(path, kind) }
             .select { |name, files| files.size >= MIN_FAMILY && !conventional?(dir, name, kind) }
             .map { |name, files| [name, files, kind] }
      end
    end

    def family_key(path, kind)
      parts = File.basename(path, ".rb").split("_")
      kind == :prefix ? parts.first : parts.last
    end

    # A suffix the directory already declares is a convention, not a family.
    # Rails puts *_controller.rb in app/controllers/ by rule, so grouping on it
    # "finds" every controller an app owns — the first repo-wide run reported 64
    # families and most were exactly that: eight controllers, twenty-one
    # reflexes, six helpers, four jobs. The suffix carries no information the
    # path does not already carry, and a shelf named for the room it stands in
    # is not a shelf.
    # Checked up the chain, not just at the basename: the shared engine puts its
    # controllers in app/controllers/shared/, so the directory that declares the
    # type is the grandparent and a basename-only test still "found" every
    # controller, helper, job and reflex it owns.
    def conventional?(dir, name, kind)
      return false unless kind == :suffix

      # Both spellings: the directory may be `rules/` holding *_rules.rb, where
      # the family key is already plural and singularising the segment misses it.
      ancestors(dir).any? { |segment| segment == name || singular(segment) == name }
    end

    # Two levels is enough for app/<type>/<namespace>/ and stops well short of
    # repo-root directory names, which are not type declarations.
    def ancestors(dir)
      absolute = File.expand_path(dir)
      [absolute, File.dirname(absolute)].map { |p| File.basename(p) }
    end

    # Enough for directory names, which are ordinary English plurals: reflexes,
    # controllers, policies, queries.
    def singular(word)
      return "#{word[0..-4]}y" if word.end_with?("ies")
      return word[0..-3] if word.end_with?("es") && !word.end_with?("ses")

      word.end_with?("s") ? word[0..-2] : word
    end

    # A file that declares a constant of its own has a boundary Zeitwerk knows
    # about; it can be moved, but it cannot be poured into a sibling.
    def namespaced?(path) = File.read(path).match?(/^\s*(module|class)\s+[A-Z]/)

    # The innermost declared constant — the one the file's path spells.
    def constant(path)
      File.read(path).scan(/^\s*(?:module|class)\s+([A-Z][\w]*)/).flatten.last
    end

    def symbols(path)
      File.read(path).scan(/^(?:def ([a-z_][\w!?]*)|([A-Z][A-Z0-9_]*)\s*=)/).flatten.compact
    end

    # Bidirectional reference is what distinguishes a family from a prefix that
    # merely reads alike. tv_show.rb and tv_channel.rb sharing "tv" is naming;
    # each calling into the other is one concept split across two files.
    def cross_references(files)
      table = files.to_h { |path| [path, symbols(path)] }
      files.sum do |path|
        body = File.read(path)
        (files - [path]).count { |other| table[other].any? { |sym| body.match?(/\b#{Regexp.escape(sym)}\b/) } }
      end
    end

    # Load order is load-bearing wherever an ordered manifest exists, so the plan
    # names the latest member as the merge site: everything the earlier members
    # read at load time is still defined by the time they run.
    def merge_plan(name, files, kind, manifest)
      ordered = manifest.empty? ? files : files.sort_by { |f| manifest.index(File.basename(f, ".rb")) || Float::INFINITY }
      {
        plan: "merge",
        family: name,
        keyed_by: kind,
        files: ordered.map { |f| File.basename(f) },
        lines: ordered.sum { |f| File.readlines(f).size },
        methods: ordered.sum { |f| File.read(f).scan(/^def [a-z_]/).size },
        merge_into: "#{name}.rb",
        take_position_of: File.basename(ordered.last, ".rb"),
        check: [
          "method and constant sets identical before and after",
          "manifest entry replaced in place, not appended",
          "no earlier member reads a constant at load time that a later one defines",
        ],
      }
    end

    # The parent is the member named exactly for the family, if there is one:
    # policy.rb already defines Ground::Policy, so the shelf it needs is its own
    # name and the rename costs nothing. Without one the regroup has to create
    # the parent module, which is a real edit and the plan says so.
    def regroup_plan(name, files, kind, dir)
      parent = files.find { |f| File.basename(f, ".rb") == name }
      members = files - [parent].compact
      subdir = File.join(dir, name)

# A destination that is already taken means the family is not one kind.
# lib/ground has memory.rb, memory_index.rb and memory_search.rb, which
# read as a family and are not: Memory::Search already exists as a mixin
# on the Memory class, while MemorySearch is a standalone keyword search
# over a repo doc index that happens to start with the same word. The
# generated plan would have moved the second on top of the first.
#
# Cheaper than any similarity heuristic, and it is the check that actually
# fires: if the shelf already holds something of that name, the two are
# different things wearing one prefix.
collisions = members.filter_map do |f|
  stem = move_for(f, name, kind)[:to]
  stem if File.exist?(File.join(dir, stem))
end
return nil if collisions.any?

      {
        plan: "regroup",
        family: name,
        keyed_by: kind,
        files: files.map { |f| File.basename(f) }.sort,
        lines: files.sum { |f| File.readlines(f).size },
        into: "#{subdir}/",
        subdirectory_exists: Dir.exist?(subdir),
        parent: parent ? File.basename(parent) : "none — #{name}.rb must be created to hold the namespace",
        moves: members.map { |f| move_for(f, name, kind) },
        check: [
          "every reference to the old constant updated — Zeitwerk resolves by path, so a stale one is a NameError at first use",
          "data/autoload.yml entries repointed if the file is listed there",
          "data/namespace_ceilings.yml counts a new namespace",
          "no member reads a sibling at load time under its old constant",
        ],
      }
    end

    def move_for(path, family, kind)
      base = File.basename(path, ".rb")
      stem = kind == :suffix ? base.delete_suffix("_#{family}") : base.delete_prefix("#{family}_")
      old_const = constant(path)
      {
        from: File.basename(path),
        to: "#{family}/#{stem}.rb",
        constant: "#{old_const} -> #{camel(family)}::#{camel(stem)}",
      }
    end

    def camel(snake) = snake.split("_").map(&:capitalize).join

    def manifest_order(dir)
      sources = File.join(File.dirname(dir), "engine_sources.rb")
      return [] unless File.file?(sources)

      File.read(sources)[/ENGINE_PARTS\s*=\s*%w\[(.*?)\]/m, 1].to_s.split(/\s+/).reject(&:empty?)
    end

    def run(dir, json: false)
      manifest = manifest_order(dir)
      found = families(dir).filter_map do |name, files, kind|
        flat = files.reject { |f| namespaced?(f) }

        if flat.size >= MIN_FAMILY
          merge_plan(name, flat, kind, manifest) if cross_references(flat) >= 2
        elsif flat.empty? && files.size >= MIN_FAMILY
          regroup_plan(name, files, kind, dir)
        end
      end
      found = dedupe(found)
      report(dir, found, json:)
      found.empty? ? 0 : 1
    end

    # A file can key into a prefix family and a suffix family at once. Keep the
    # larger; report the same surgery once.
    def dedupe(found)
      found.sort_by { |p| -p[:files].size }
           .each_with_object([]) do |plan, kept|
             kept << plan unless kept.any? { |k| (k[:files] & plan[:files]).size >= MIN_FAMILY }
           end
    end

    def report(dir, found, json:)
      return puts(JSON.pretty_generate(dir:, families: found)) if json

      merges = found.count { |p| p[:plan] == "merge" }
      regroups = found.size - merges
      puts "cohesion: #{dir} — #{found.size} family/families that read as one concept " \
           "(#{merges} to merge, #{regroups} to regroup)"
      found.each { |plan| plan[:plan] == "merge" ? print_merge(plan) : print_regroup(plan) }
      puts(found.empty? ? "cohesion: nothing to merge" : "cohesion: run the checks in --json before touching anything")
    end

    def print_merge(plan)
      puts "  #{plan[:family]} [merge, by #{plan[:keyed_by]}]: #{plan[:files].size} files, " \
           "#{plan[:lines]} lines, #{plan[:methods]} methods"
      puts "    #{plan[:files].join(' + ')}"
      puts "    -> #{plan[:merge_into]}, taking #{plan[:take_position_of]}'s position in the load order"
    end

    def print_regroup(plan)
      puts "  #{plan[:family]} [regroup, by #{plan[:keyed_by]}]: #{plan[:files].size} files, #{plan[:lines]} lines"
      puts "    #{plan[:files].join(' + ')}"
      puts "    -> #{plan[:into]}#{plan[:subdirectory_exists] ? ' (exists already)' : ''}, parent #{plan[:parent]}"
      plan[:moves].each { |m| puts "       #{m[:from]} -> #{m[:to]}   #{m[:constant]}" }
    end

    # ---- census -------------------------------------------------------------
    #
    # One directory at a time answers "what should I merge here"; it does not
    # answer "is the tree getting neater". This does, and it is the half that
    # makes the tool convergent instead of advisory: a number with a recorded
    # low, in the shape data/dup_census.yml and data/namespace_ceilings.yml
    # already use. `lint:cohesion` printed proposals and exited 0 for its whole
    # life, and it was not in `rake audit` either, so nothing ever read them.
    CENSUS = File.expand_path("../data/cohesion_census.yml", __dir__)
    REPO = File.expand_path("../..", __dir__)

    # Where families are worth naming. Deliberately not "every directory": db/,
    # test fixtures and vendored trees have families by construction and
    # counting them would drown the signal the roots below carry.
    ROOTS = %w[
      MASTER/lib MASTER/law MASTER/tools MASTER/web/app
      RAILS/shared/app RAILS/shared/lib RAILS/gates
      RAILS/brgen/app RAILS/brgen/lib RAILS/amber/app RAILS/amber/lib
      RAILS/bsdports/app RAILS/bsdports/lib
      STUDIO/dilla/lib STUDIO/lora STUDIO/postpro STUDIO/repligen
      OPENBSD/lib
    ].freeze

    SKIP = %r{/(vendor|node_modules|tmp|log|\.git|fixtures|dummy)/}

    # A census that reports the repo-wide number under every tree's heading is
# four copies of one fact wearing four names. --tree scopes it.
def roots_for(tree) = tree ? ROOTS.select { |r| r == tree || r.start_with?("#{tree}/") } : ROOTS

def census_dirs(tree = nil)
      roots_for(tree).flat_map { |root| Dir.glob(File.join(REPO, root, "**/")) + [File.join(REPO, root)] }
           .map { |d| d.chomp("/") }.uniq.reject { |d| d.match?(SKIP) }
           .select { |d| Dir.glob(File.join(d, "*.rb")).size >= MIN_FAMILY }
    end

    def census(tree = nil)
      census_dirs(tree).sort.filter_map do |dir|
        plans = plans_for(dir)
        [dir.sub("#{REPO}/", "").chomp("/"), plans] unless plans.empty?
      end
    end

    def plans_for(dir)
      found = families(dir).filter_map do |name, files, kind|
        flat = files.reject { |f| namespaced?(f) }
        if flat.size >= MIN_FAMILY
          merge_plan(name, flat, kind, manifest_order(dir)) if cross_references(flat) >= 2
        elsif flat.empty? && files.size >= MIN_FAMILY
          regroup_plan(name, files, kind, dir)
        end
      end
      dedupe(found)
    end

    def ceiling
      File.exist?(CENSUS) ? YAML.safe_load_file(CENSUS).fetch("families", 0) : 0
    end

    def run_census(ratchet: false, list: false, tree: nil)
      rows = census(tree)
      total = rows.sum { |_, plans| plans.size }
      scope = tree ? " in #{tree}" : ""
      ceil = tree ? "-" : ceiling
      puts "cohesion_census: #{total} family/families across #{rows.size} directories#{scope} (ceiling #{ceil})"

      if list
        rows.each do |dir, plans|
          puts "  #{dir}"
          plans.each { |p| puts format("     %-8s %-12s %2d files %5d lines", p[:plan], p[:family], p[:files].size, p[:lines]) }
        end
        return 0
      end

      return 0 if tree

      if ratchet && total < ceiling
        File.write(CENSUS, { "families" => total }.to_yaml)
        puts "cohesion_census: recorded #{total} as the new low"
        return 0
      end
      return 0 unless total > ceiling

      rows.sort_by { |_, plans| -plans.sum { |p| p[:lines] } }.first(6).each do |dir, plans|
        puts "  #{dir}: #{plans.map { |p| "#{p[:family]} (#{p[:files].size})" }.join(', ')}"
      end
      puts "cohesion_census: a new family appeared — regroup it, merge it, or price the ceiling"
      1
    end

  end
end

if $PROGRAM_NAME == __FILE__
  if ARGV.include?("--census")
    tree = ARGV.grep(/\A--tree=/).first&.split("=", 2)&.last
    exit Pub4::Cohesion.run_census(ratchet: ARGV.include?("--ratchet"), list: ARGV.include?("--list"), tree:)
  end

  target = ARGV.reject { |a| a.start_with?("--") }.first
  abort "usage: cohesion.rb <dir> | cohesion.rb --census [--list|--ratchet]" unless target
  exit Pub4::Cohesion.run(target, json: ARGV.include?("--json"))
end
