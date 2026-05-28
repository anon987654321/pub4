#!/usr/bin/env ruby
# frozen_string_literal: true

# DEPLOY/sh/tools/tree.rb
#
# Constitution-aware project tree for pub4.
# Respects skip_dirs from MASTER/data/rules.yml + aggressive pruning for overview.
# Usage: ruby tree.rb [root] [--max-depth=3] [--summary]
#
# This exists because DEPLOY/sh/tree.sh was referenced for full overview
# during major KISS/DRY architectural work on MASTER.

require "yaml"
require "optparse"

class ProjectTree
  DEFAULT_SKIP = %w[
    .git vendor tmp var node_modules .bundle coverage log dist
    knowledge github_repos
    DEPLOY/openbsd/var DEPLOY/rails
  ].freeze

  def initialize(root:, max_depth: 4, summary: false)
    @root = File.expand_path(root)
    @max_depth = max_depth
    @summary = summary
    @skip = load_skip_dirs
    @counts = Hash.new(0)
  end

  def run
    puts "pub4/ (constitution-aware tree, skips: #{@skip.join(', ')})"
    puts

    walk(@root, "", 0)

    if @summary
      puts
      puts "Summary (top-level counts):"
      @counts.sort_by { |k, v| -v }.first(20).each do |k, v|
        puts "  #{k}: #{v}"
      end
    end
  end

  private

  def load_skip_dirs
    rules_path = File.join(@root, "MASTER/data/rules.yml")
    return DEFAULT_SKIP unless File.exist?(rules_path)

    begin
      data = YAML.safe_load_file(rules_path, permitted_classes: [Symbol], aliases: true) || {}
      from_yml = data.dig("paths", "skip_dirs") || []
      (from_yml + DEFAULT_SKIP).map(&:to_s).uniq
    rescue
      DEFAULT_SKIP
    end
  end

  def should_skip?(path)
    rel = path.sub(@root + "/", "")
    @skip.any? { |s| rel.start_with?(s) || rel == s }
  end

  def walk(dir, prefix, depth)
    return if depth > @max_depth

    entries = begin
      Dir.entries(dir).sort
    rescue
      return
    end

    entries.reject! { |e| e.start_with?(".") && !%w[. ..].include?(e) } # hide most dots for clean overview
    entries.reject! { |e| %w[. ..].include?(e) }

    files = []
    dirs = []

    entries.each do |e|
      full = File.join(dir, e)
      next if should_skip?(full)

      if File.directory?(full)
        dirs << e
      else
        files << e
      end
    end

    # Print files first (importance order style)
    files.each_with_index do |f, i|
      last = (i == files.size - 1) && dirs.empty?
      branch = last ? "└── " : "├── "
      puts "#{prefix}#{branch}#{f}"
      @counts["files"] += 1
    end

    # Then subdirs
    dirs.each_with_index do |d, i|
      last = i == dirs.size - 1
      branch = last ? "└── " : "├── "
      full_path = File.join(dir, d)
      puts "#{prefix}#{branch}#{d}/"

      @counts["dirs"] += 1

      new_prefix = prefix + (last ? "    " : "│   ")
      walk(full_path, new_prefix, depth + 1)
    end
  end
end

if __FILE__ == $PROGRAM_NAME
  options = { max_depth: 4, summary: false, root: ARGV[0] || Dir.pwd }

  OptionParser.new do |opts|
    opts.on("--max-depth=N", Integer) { |n| options[:max_depth] = n }
    opts.on("--summary", "Show counts") { options[:summary] = true }
    opts.on("-h", "--help") do
      puts opts
      exit
    end
  end.parse!(ARGV)

  root = options[:root]
  ProjectTree.new(root: root, max_depth: options[:max_depth], summary: options[:summary]).run
end
