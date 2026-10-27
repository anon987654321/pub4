# frozen_string_literal: true

require "fileutils"
require "open3"
require "optparse"

module Operator
  class Worktree
    ROOT = File.expand_path("../../..", __dir__)
    NAME = /\A[a-zA-Z0-9][a-zA-Z0-9._-]{0,63}\z/
    Entry = Data.define(:name, :path, :branch, :revision)

    class Error < StandardError; end

    attr_reader :root, :managed_root

    def initialize(root: ROOT)
      @root = File.realpath(root)
      top, ok = run("rev-parse", "--show-toplevel")
      raise Error, "not a Git checkout: #{root}" unless ok
      raise Error, "expected repository root #{top.strip}, received #{@root}" unless File.realpath(top.strip) == @root

      @managed_root = File.join(File.dirname(@root), ".#{File.basename(@root)}-worktrees")
    end

    def create(name, base: "HEAD", allow_dirty_source: false)
      name = validate_name(name)
      base = validate_base(base)
      branch = "work/#{name}"
      path = managed_path(name)

      status = git!("status", "--porcelain", "--untracked-files=all")
      unless status.empty? || allow_dirty_source
        raise Error, "source checkout is dirty; commit the changes or pass --allow-dirty-source to create from #{base} without copying uncommitted changes"
      end

      git!("check-ref-format", "--branch", branch)
      raise Error, "branch #{branch} already exists; choose another name or inspect it with bin/operator branches" if branch_exists?(branch)

      revision = git!("rev-parse", "--verify", "#{base}^{commit}").strip
      ensure_managed_root!(create: true)
      raise Error, "worktree path already exists: #{path}" if File.exist?(path) || File.symlink?(path)
      git!("worktree", "add", "-b", branch, path, revision)
      Entry.new(name:, path:, branch:, revision:)
    end

    def list
      return [] unless ensure_managed_root!(create: false)

      registered_worktrees.filter_map do |entry|
        path = File.expand_path(entry[:path])
        next unless path.start_with?("#{managed_root}#{File::SEPARATOR}")

        Entry.new(name: File.basename(path), path:, branch: entry[:branch].to_s, revision: entry[:revision].to_s)
      end
    end

    def remove(name)
      name = validate_name(name)
      raise Error, "no registered managed worktree named #{name}" unless ensure_managed_root!(create: false)

      path = managed_path(name)
      entry = registered_worktrees.find { |item| File.expand_path(item[:path]) == path }
      raise Error, "no registered managed worktree named #{name}" unless entry
      raise Error, "refusing to remove unexpected path #{entry[:path]}" unless
        File.expand_path(entry[:path]).start_with?("#{managed_root}#{File::SEPARATOR}")

      # Git refuses dirty worktrees by default. Never add --force: uncommitted work
      # is evidence to preserve, not a cleanup inconvenience.
      git!("worktree", "remove", path)
      { name:, path:, branch: entry[:branch].to_s }
    end

    def self.command(argv, root: ROOT)
      args = Array(argv).dup
      action = %w[create list remove].include?(args.first) ? args.shift : "create"
      manager = new(root:)

      case action
      when "list"
        raise Error, "usage: bin/operator worktree list" unless args.empty?
        rows = manager.list
        if rows.empty?
          puts "worktree0: no managed worktrees"
        else
          rows.each { |row| puts "worktree0: #{row.branch} #{row.path} (HEAD #{row.revision[0, 12]})" }
        end
      when "remove"
        name = args.shift
        raise Error, "usage: bin/operator worktree remove <name>" if name.to_s.empty? || !args.empty?
        row = manager.remove(name)
        puts "worktree0: removed #{row[:path]}; branch #{row[:branch]} preserved"
      when "create"
        name = args.shift
        raise Error, "usage: bin/operator worktree <name> [--base REF] [--allow-dirty-source]" if name.to_s.empty?
        options = { base: "HEAD", allow_dirty_source: false }
        parser = OptionParser.new do |opts|
          opts.on("--base REF", "commit or ref to start from (default: HEAD)") { |value| options[:base] = value }
          opts.on("--allow-dirty-source", "create from selected commit without copying uncommitted changes") do
            options[:allow_dirty_source] = true
          end
        end
        parser.parse!(args)
        raise Error, "unexpected arguments: #{args.join(" ")}" unless args.empty?
        row = manager.create(name, **options)
        puts "worktree0: created #{row.branch} at #{row.path} from #{row.revision[0, 12]}"
      else
        raise Error, "usage: bin/operator worktree <name> | list | remove <name>"
      end
      0
    rescue StandardError => e
      warn "worktree0: failed, #{e.message}"
      1
    end

    private

    def validate_name(name)
      value = name.to_s
      raise Error, "invalid worktree name #{value.inspect}; use 1–64 ASCII letters, digits, dots, underscores or hyphens" unless NAME.match?(value)

      value
    end

    def validate_base(base)
      value = base.to_s.strip
      raise Error, "base ref must be nonempty and cannot start with -" if value.empty? || value.start_with?("-")

      value
    end

    def managed_path(name)
      File.join(managed_root, validate_name(name))
    end

    def ensure_managed_root!(create:)
      raise Error, "managed worktree directory may not be a symlink: #{managed_root}" if File.symlink?(managed_root)
      if create
        FileUtils.mkdir_p(managed_root)
      else
        return false unless File.directory?(managed_root)
      end

      resolved = File.realpath(managed_root)
      expected = File.expand_path(managed_root)
      raise Error, "managed worktree directory resolves outside its declared location" unless resolved == expected

      true
    end

    def branch_exists?(branch)
      _out, status = run("show-ref", "--verify", "--quiet", "refs/heads/#{branch}")
      status
    end

    def registered_worktrees
      data = git!("worktree", "list", "--porcelain")
      data.split(/\n\n+/).filter_map do |block|
        lines = block.lines(chomp: true)
        path = lines.find { |line| line.start_with?("worktree ") }&.delete_prefix("worktree ")
        next unless path

        {
          path:,
          branch: lines.find { |line| line.start_with?("branch ") }&.delete_prefix("branch ")&.delete_prefix("refs/heads/"),
          revision: lines.find { |line| line.start_with?("HEAD ") }&.delete_prefix("HEAD "),
        }
      end
    end

    def git!(*args)
      output, ok = run(*args)
      raise Error, "git #{args.join(" ")} failed: #{output.lines.first(8).join.strip}" unless ok

      output
    end

    def run(*args)
      output, status = Open3.capture2e("git", "-C", root, *args)
      [output, status.success?]
    rescue Errno::ENOENT => e
      raise Error, "git executable unavailable: #{e.message}"
    end
  end
end
