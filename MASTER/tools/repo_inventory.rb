#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"

# INVENTORY_ROOT, not ROOT. A bare top-level ROOT is harmless in its own process
# and stops being harmless the moment two of them load together: Ruby warns
# "already initialized constant", lets the second assignment win, and the loser
# reads the wrong tree with no further complaint. Made the spec that reads this
# file's constants collide with spec/dogfood_spec.rb's ROOT on the first run.
# tools/security_sweep.rb is SWEEP_ROOT for the same reason.
INVENTORY_ROOT = File.expand_path("../..", __dir__)
# Both lists had gone stale in both directions at once, which is the worst state
# an allowlist can be in: five of seven files and four of six directories named
# subjects that no longer exist, while the four canonical trees, TODO.md and
# TREE.md were absent — so this tool reported MASTER, RAILS, OPENBSD and STUDIO
# as non-canonical top-level directories. A report that names the repo's own
# trees as sprawl is one nobody acts on, and that is how it stayed wrong.
#
# CLAUDE.md says what belongs at the root: itself, TODO.md, TREE.md, and nothing
# else. The three harness files beside it are generated from MASTER/AGENTS.md by
# `rake docs:agent_contracts` and have to sit where their agent reads them.
# spec/lifecycle_tools_spec.rb holds both lists to the tree in both directions.
ALLOWED_ROOT_FILES = %w[
  .cursorrules
  .gitattributes
  .gitignore
  .ruby-version
  AGENTS.md
  CLAUDE.md
  GEMINI.md
  TODO.md
  TREE.md
].freeze
ALLOWED_ROOT_DIRS = %w[
  .claude
  .github
  MASTER
  OPENBSD
  RAILS
  STUDIO
].freeze
SKIP_DIRS = %w[
  .git
  .bundle
  node_modules
  vendor
  tmp
  log
  coverage
].freeze

Entry = Struct.new(:path, :kind, :reason, keyword_init: true)

def repo_paths
  Dir.glob(File.join(INVENTORY_ROOT, "**/*"), File::FNM_DOTMATCH).reject do |path|
    next true if [".", ".."].include?(File.basename(path))
    parts = path.split(File::SEPARATOR)
    parts.any? { |part| SKIP_DIRS.include?(part) }
  end
end

def root_entries
  Dir.children(INVENTORY_ROOT).reject { |name| name == ".git" }.sort
end

def loose_root_entries
  root_entries.filter_map do |name|
    full_path = File.join(INVENTORY_ROOT, name)
    if File.directory?(full_path)
      next if ALLOWED_ROOT_DIRS.include?(name)
      Entry.new(path: name, kind: "root_dir", reason: "non-canonical top-level directory")
    else
      next if ALLOWED_ROOT_FILES.include?(name)
      Entry.new(path: name, kind: "root_file", reason: "non-canonical top-level file")
    end
  end
end

def duplicate_basename_entries
  groups = repo_paths.select { |path| File.file?(File.join(INVENTORY_ROOT, path)) }.group_by { |path| File.basename(path) }
  groups.filter_map do |basename, paths|
    next if paths.size < 2
    next if basename.start_with?(".")
    Entry.new(path: paths.sort.join(" | "), kind: "duplicate_basename", reason: "same filename appears in multiple locations")
  end
end

def low_density_slug_entries
  require File.expand_path("../lib/ground/parameterized_slug.rb", __dir__)
  slug = Master::Ground::ParameterizedSlug

  repo_paths.filter_map do |path|
    next unless path.end_with?(".rb")

    stem = File.basename(path, ".rb")
    next unless slug.filler_only?(stem) || slug.fold_suffix?(stem) || slug.meaningful_tokens(stem).size < stem.split("_").size

    Entry.new(path:, kind: "low_density_slug", reason: "not a dense Rails-parameterize slug — merge or rename (Flat Hierarchy)")
  end
end

# `new` was in this list and had no true positive in the repo. Thirty-four of its
# thirty-five findings were `app/views/**/new.html.erb`, which is a Rails route
# action rather than "the new version of a file", and the thirty-fifth was
# `new_framework_defaults_8_0.rb`, a name Rails generates. A marker that only
# ever matches a framework convention is measuring the convention. The rest keep
# their meaning without colliding with one.
SUSPICIOUS_MARKERS = "bp|tmp|misc|old|copy|final|final2|test2"

def suspicious_abbreviation_entries
  basename_marker = /\A(#{SUSPICIOUS_MARKERS})(\.|\z|_)/i
  path_marker = %r{/(#{SUSPICIOUS_MARKERS})(/|\.)}i
  repo_paths.filter_map do |path|
    next unless File.basename(path).match?(basename_marker) || path.match?(path_marker)

    Entry.new(path:, kind: "suspicious_name", reason: "abbreviation or temporary filename")
  end
end

def report(argv)
  entries = (loose_root_entries + duplicate_basename_entries + suspicious_abbreviation_entries + low_density_slug_entries)
    .uniq { |entry| [entry.path, entry.kind] }
    .sort_by { |entry| [entry.kind, entry.path] }

  return puts(JSON.pretty_generate(entries.map(&:to_h))) if argv.include?("--json")
  return puts("ok: no repo sprawl detected") if entries.empty?

  entries.each { |entry| puts "#{entry.kind}: #{entry.path} — #{entry.reason}" }
  abort "err: repo sprawl detected (#{entries.size})"
end

# The guard every other tool here carries. Without it, reading the two
# allowlists from this file meant running the whole census and aborting, so the
# spec that holds them to the tree could not name the constants that own them —
# and a spec reading them out of the source text as strings is the restatement
# these lists already suffered from.
report(ARGV) if $PROGRAM_NAME == __FILE__
