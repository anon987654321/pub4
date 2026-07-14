#!/usr/bin/env ruby
# frozen_string_literal: true

ROOT = File.expand_path("../..", __dir__)

SKIP_DIRS = %w[
  .git vendor node_modules .bundle storage log tmp lora
  _latent_cache knowledge web/public/assets web/vendor
].freeze

SKIP_FILES = %w[
  snapshot_DEPLOY.md snapshot_MASTER.md MIGRATION.md migrate_deploy_paths.rb
].freeze

REPLACEMENTS = [
  [%r{RAILS}, "RAILS"],
  [%r{OPENBSD}, "OPENBSD"],
  [%r{OPENBSD/}, "OPENBSD/"],
  [%r{\bDEPLOY\b(?!/)}, "OPENBSD"],
].freeze

def candidate_files
  files = []
  Dir.glob(File.join(ROOT, "**", "*"), File::FNM_DOTMATCH) do |path|
    next unless File.file?(path)
    next if SKIP_FILES.include?(File.basename(path))
    next if SKIP_DIRS.any? { |part| path.include?("/#{part}/") }

    ext = File.extname(path)
    next unless ext.match?(/\.(rb|yml|yaml|md|sh|zsh|ksh|exp|json|erb|scss|css|js|txt|ru|rake|gemspec|conf|local|html|mjs|rbenv|gitignore|gitattributes|yml\.erb)$/i) ||
                path.end_with?("Procfile.dev", "Gemfile", "Rakefile", "Dockerfile", "rc.d", "master.json")

    files << path
  end
  files
end

changed = []
candidate_files.each do |path|
  body = File.read(path, encoding: "UTF-8", invalid: :replace, undef: :replace)
  next unless body.include?("DEPLOY")

  updated = body.dup
  REPLACEMENTS.each { |pattern, sub| updated.gsub!(pattern, sub) }
  next if updated == body

  File.write(path, updated)
  changed << path.sub("#{ROOT}/", "")
end

puts "migrate_deploy_paths: updated #{changed.size} files"
changed.sort.each { |rel| puts "  #{rel}" }