#!/usr/bin/env ruby
# frozen_string_literal: true

# frozen_string_literal: true
# frozen_string_literal: true

require "json"

ROOT = File.expand_path("../..", __dir__)
ALLOWED_ROOT_FILES = %w[
  .gitignore
  CLAUDE.md
  Gemfile
  LICENSE
  MASTER.md
  README.md
  index.html
].freeze
ALLOWED_ROOT_DIRS = %w[
  .github
  OPERATOR
  MASTER
  dilla
  multimedia
  sh
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
  Dir.glob(File.join(ROOT, "**/*"), File::FNM_DOTMATCH).reject do |path|
    next true if [".", ".."].include?(File.basename(path))
    parts = path.split(File::SEPARATOR)
    parts.any? { |part| SKIP_DIRS.include?(part) }
  end
end

def root_entries
  Dir.children(ROOT).reject { |name| name == ".git" }.sort
end

def loose_root_entries
  root_entries.filter_map do |name|
    full_path = File.join(ROOT, name)
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
  groups = repo_paths.select { |path| File.file?(File.join(ROOT, path)) }.group_by { |path| File.basename(path) }
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

def suspicious_abbreviation_entries
  repo_paths.filter_map do |path|
    basename = File.basename(path)
    next unless basename.match?(/\A(bp|tmp|misc|old|new|copy|final|final2|test2)(\.|\z|_)/i) || path.match?(%r{/(bp|tmp|misc|old|new|copy|final|final2|test2)(/|\.)}i)
    Entry.new(path:, kind: "suspicious_name", reason: "abbreviation or temporary filename")
  end
end

entries = (loose_root_entries + duplicate_basename_entries + suspicious_abbreviation_entries + low_density_slug_entries)
  .uniq { |entry| [entry.path, entry.kind] }
  .sort_by { |entry| [entry.kind, entry.path] }

if ARGV.include?("--json")
  puts JSON.pretty_generate(entries.map(&:to_h))
else
  if entries.empty?
    puts "ok: no repo sprawl detected"
  else
    entries.each do |entry|
      puts "#{entry.kind}: #{entry.path} — #{entry.reason}"
    end
    abort "err: repo sprawl detected (#{entries.size})"
  end
end
