# frozen_string_literal: true

# Files that are one concept wearing several names.
#
# Every structural rule in data/rules.yml points one way: SMALL_FILES,
# NO_GOD_CLASS and INTEGRATED_SYSTEMS all say "split further". Nothing says
# "these three are one thing", so no scan has ever proposed a merge — which is
# why STUDIO/dilla carried patch_catalog, patch_pools and patch_select as three
# files referring to each other in both directions, in one flat namespace, for
# as long as it did.
#
#   ruby MASTER/tools/cohesion.rb STUDIO/dilla/lib/engine
#   ruby MASTER/tools/cohesion.rb --json RAILS/shared/lib
#
# It emits a plan rather than a patch. Moving code between files is not a
# line-level edit and MASTER's autofix transforms are all line-level; a merge
# also has to respect load order, which is a property of the tree and not of any
# file. So this states what to merge, in what order, and what to check — and a
# person or a model does the surgery.

require "json"

module Pub4
  module Cohesion
    MIN_FAMILY = 3

    module_function

    def families(dir)
      Dir.glob(File.join(dir, "*.rb")).group_by { |path| File.basename(path, ".rb").split("_").first }
         .select { |_, files| files.size >= MIN_FAMILY }
    end

    # A file that declares a module or class already has a boundary; merging it
    # is a different and larger question than merging files that share one.
    def namespaced?(path) = File.read(path).match?(/^\s*(module|class)\s+[A-Z]/)

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
    def plan_for(name, files, manifest)
      ordered = manifest.empty? ? files : files.sort_by { |f| manifest.index(File.basename(f, ".rb")) || Float::INFINITY }
      {
        family: name,
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

    def manifest_order(dir)
      sources = File.join(File.dirname(dir), "engine_sources.rb")
      return [] unless File.file?(sources)

      File.read(sources)[/ENGINE_PARTS\s*=\s*%w\[(.*?)\]/m, 1].to_s.split(/\s+/).reject(&:empty?)
    end

    def run(dir, json: false)
      manifest = manifest_order(dir)
      found = families(dir).filter_map do |name, files|
        flat = files.reject { |f| namespaced?(f) }
        next if flat.size < MIN_FAMILY || cross_references(flat) < 2

        plan_for(name, flat, manifest)
      end
      report(dir, found, json:)
      found.empty? ? 0 : 1
    end

    def report(dir, found, json:)
      return puts(JSON.pretty_generate(dir:, families: found)) if json

      puts "cohesion: #{dir} — #{found.size} family/families that read as one concept"
      found.each do |plan|
        puts "  #{plan[:family]}: #{plan[:files].size} files, #{plan[:lines]} lines, #{plan[:methods]} methods"
        puts "    #{plan[:files].join(' + ')}"
        puts "    -> #{plan[:merge_into]}, taking #{plan[:take_position_of]}'s position in the load order"
      end
      puts(found.empty? ? "cohesion: nothing to merge" : "cohesion: run the checks in --json before merging")
    end
  end
end

if $PROGRAM_NAME == __FILE__
  target = ARGV.reject { |a| a.start_with?("--") }.first
  abort "usage: cohesion.rb [--json] <dir>" unless target
  exit Pub4::Cohesion.run(target, json: ARGV.include?("--json"))
end
