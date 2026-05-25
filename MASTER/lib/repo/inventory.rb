# frozen_string_literal: true

require "json"
require_relative "../master_paths"

module Repo
  Entry = Struct.new(:path, :kind, :reason, keyword_init: true) do
    def to_h = { path: path, kind: kind, reason: reason }
  end

  class Inventory
    ALLOWED_ROOT_FILES = %w[.gitignore CLAUDE.md Gemfile LICENSE MASTER.md README.md index.html].freeze
    ALLOWED_ROOT_DIRS = %w[.github DEPLOY MASTER dilla multimedia sh].freeze
    SKIP_DIRS = %w[.git .bundle node_modules vendor tmp log coverage].freeze
    TEMP_NAME = /\A(bp|tmp|misc|old|new|copy|final|final2|test2)(\.|\z|_)/i
    TEMP_PATH = %r{/(bp|tmp|misc|old|new|copy|final|final2|test2)(/|\.)}i

    def initialize(root: MasterPaths.repo)
      @root = root
    end

    def entries
      (loose_root_entries + duplicate_basename_entries + suspicious_abbreviation_entries)
        .uniq { |entry| [entry.path, entry.kind] }
        .sort_by { |entry| [entry.kind, entry.path] }
    end

    def to_json(*args) = JSON.pretty_generate(entries.map(&:to_h), *args)

    private

    attr_reader :root

    def repo_paths
      Dir.chdir(root) do
        Dir.glob("**/*", File::FNM_DOTMATCH).reject do |path|
          next true if [".", ".."].include?(File.basename(path))
          path.split(File::SEPARATOR).any? { |part| SKIP_DIRS.include?(part) }
        end
      end
    end

    def root_entries
      Dir.chdir(root) { Dir.children(".").reject { |name| name == ".git" }.sort }
    end

    def loose_root_entries
      root_entries.filter_map do |name|
        full_path = File.join(root, name)
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
      groups = repo_paths.select { |path| File.file?(File.join(root, path)) }.group_by { |path| File.basename(path) }
      groups.filter_map do |basename, paths|
        next if paths.size < 2 || basename.start_with?(".")
        Entry.new(path: paths.sort.join(" | "), kind: "duplicate_basename", reason: "same filename appears in multiple locations")
      end
    end

    def suspicious_abbreviation_entries
      repo_paths.filter_map do |path|
        basename = File.basename(path)
        next unless basename.match?(TEMP_NAME) || path.match?(TEMP_PATH)
        Entry.new(path: path, kind: "suspicious_name", reason: "abbreviation or temporary filename")
      end
    end
  end
end
