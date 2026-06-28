#!/usr/bin/env ruby
# frozen_string_literal: true

# One-shot: fold runtime-read MD into YAML authority files.
# Safe to re-run; overwrites data/operator_principles.yml, skills_registry.yml, project_context.yml.

require "yaml"
require "fileutils"

ROOT = File.expand_path("..", __dir__)
DATA = File.join(ROOT, "data")

def parse_frontmatter(path)
  raw = File.read(path, encoding: "UTF-8")
  return { meta: {}, body: raw.strip } unless raw.start_with?("---\n")

  match = raw.match(/\A---\n(.*?)\n---\n?(.*)/m)
  return { meta: {}, body: raw.strip } unless match

  meta = YAML.safe_load(match[1], permitted_classes: [Symbol, Time, Date]) || {}
  { meta: meta, body: match[2].strip }
rescue StandardError
  { meta: {}, body: "" }
end

def migrate_principles
  dir = File.join(DATA, "principles")
  rows = Dir.glob(File.join(dir, "*.md")).sort.filter_map do |path|
    fm = parse_frontmatter(path)
    next if fm[:meta].empty?

    {
      "id" => File.basename(path, ".md"),
      "name" => fm[:meta]["name"].to_s,
      "description" => fm[:meta]["description"].to_s,
      "type" => fm[:meta]["type"].to_s,
      "body" => fm[:body][0, 320]
    }
  end

  out = { "meta" => { "source" => "data/principles/*.md", "count" => rows.size }, "principles" => rows }
  File.write(File.join(DATA, "operator_principles.yml"), out.to_yaml)
  puts "operator_principles.yml: #{rows.size} principles"
end

def migrate_skills
  dir = File.join(DATA, "skills")
  rows = Dir.glob(File.join(dir, "*.md")).sort.filter_map do |path|
    next if File.basename(path) == "README.md"

    fm = parse_frontmatter(path)
    {
      "name" => (fm[:meta]["name"] || File.basename(path, ".md")).to_s,
      "description" => fm[:meta]["description"].to_s,
      "triggers" => Array(fm[:meta]["triggers"]),
      "body" => fm[:body]
    }
  end

  out = { "meta" => { "source" => "data/skills/*.md", "count" => rows.size }, "skills" => rows }
  File.write(File.join(DATA, "skills_registry.yml"), out.to_yaml)
  puts "skills_registry.yml: #{rows.size} skills"
end

def migrate_project_context
  dir = File.join(DATA, "claude")
  rows = Dir.glob(File.join(dir, "*.md")).sort.map do |path|
    fm = parse_frontmatter(path)
    {
      "key" => File.basename(path, ".md"),
      "name" => fm[:meta]["name"].to_s,
      "description" => fm[:meta]["description"].to_s,
      "type" => (fm[:meta]["type"].to_s.empty? ? "general" : fm[:meta]["type"]).to_s,
      "body" => fm[:body]
    }
  end

  out = { "meta" => { "source" => "data/claude/*.md", "count" => rows.size }, "entries" => rows }
  File.write(File.join(DATA, "project_context.yml"), out.to_yaml)
  puts "project_context.yml: #{rows.size} entries"
end

migrate_principles
migrate_skills
migrate_project_context
puts "done"