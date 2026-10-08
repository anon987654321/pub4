# frozen_string_literal: true

require_relative "../io/exec"
require "set"
require "yaml"

module Operator
  # A commit that changes a measured source population must carry the ceiling
  # that prices that population in the same commit. This is deliberately a
  # narrow, cheap pre-delivery guard: it catches source-file growth/deletion and
  # real MASTER/lib body-line growth without rerunning the full ratchet census.
  module RatchetSponsor
    TREE_CEILING = "MASTER/data/spine.yml"
    SOURCE_EXTENSIONS = %w[.rb .rake .erb .scss .css .js .mjs .yml .yaml .md .sh .ksh .exp .html .json].freeze
    TREES = %w[MASTER RAILS OPENBSD STUDIO].freeze
    EXCLUDED_DIRS = %r{/(vendor|node_modules|tmp|coverage|log|\.master|knowledge|output|renders|samples)/}

    module_function

    def validate!(root:, changed_paths:)
      paths = Array(changed_paths).map { |path| path.to_s.sub(%r{\A\./}, "") }.reject(&:empty?).uniq
      return true if paths.empty?
      return true unless git_checkout?(root)

      tree_deltas, additions, deletions = source_population_delta(root, paths)
      body_delta = master_lib_body_delta(root, paths)

      return true if additions.zero? && deletions.zero? && body_delta.zero?
      return true if sponsored_ceiling?(root, tree_deltas, body_delta)

      raise "ratchet sponsorship required: #{TREE_CEILING} must change with source growth/deletion " \
            "(files +#{additions}/-#{deletions}, MASTER/lib body #{format("%+d", body_delta)} lines)"
    end
    def source_population_delta(root, paths)
      tracked = tracked_paths(root)
      statuses = diff_statuses(root, paths)
      deltas = Hash.new(0)

      statuses.each do |path, state|
        next unless source_path?(path)

        tree = path.split("/", 2).first
        deltas[tree] += 1 if state.start_with?("A")
        deltas[tree] -= 1 if state.start_with?("D")
      end

      paths.each do |path|
        next unless source_path?(path) && !statuses.key?(path)

        tree = path.split("/", 2).first
        deltas[tree] += 1 if !tracked.include?(path)
        deltas[tree] -= 1 if tracked.include?(path) && !File.exist?(File.join(root, path))
      end

      additions = deltas.values.select(&:positive?).sum
      deletions = -deltas.values.select(&:negative?).sum
      [deltas, additions, deletions]
    end
    def master_lib_body_delta(root, paths)
      lib_paths = paths.select { |path| path.start_with?("MASTER/lib/") }
      return 0 if lib_paths.empty?

      tracked = tracked_paths(root)
      untracked_body = lib_paths.filter_map do |path|
        next if tracked.include?(path)

        full = File.join(root, path)
        next unless File.file?(full)

        File.read(full, encoding: "UTF-8").lines.count { |line| !body_ignorable?(line) }
      end.sum

      out, status = Master::Io::Exec.capture2e("git", "-C", root, "diff", "--unified=0", "HEAD", "--", *lib_paths)
      return 0 unless status.success?

      added = 0
      deleted = 0
      out.each_line do |line|
        next if line.start_with?("+++", "---", "@@")
        next if body_ignorable?(line[1..].to_s)

        if line.start_with?("+")
          added += 1
        elsif line.start_with?("-")
          deleted += 1
        end
      end
      added - deleted + untracked_body
    end
    def sponsored_ceiling?(root, tree_deltas, body_delta)
      before, status = Master::Io::Exec.capture2e("git", "-C", root, "show", "HEAD:#{TREE_CEILING}")
      raise "ratchet sponsorship: #{TREE_CEILING} unreadable at HEAD: #{before}" unless status.success?

      old = YAML.safe_load(before, aliases: true)
      current = YAML.safe_load_file(File.join(root, TREE_CEILING), aliases: true)
      old_source = old.fetch("pub4_source_ceilings", {})
      current_source = current.fetch("pub4_source_ceilings", {})
      source_ok = tree_deltas.all? { |tree, delta| delta.zero? || old_source[tree].to_i != current_source[tree].to_i }
      body_ok = body_delta.zero? || old.dig("spine", "lib_body_ceiling").to_i != current.dig("spine", "lib_body_ceiling").to_i
      source_ok && body_ok
    rescue Psych::Exception => e
      raise "ratchet sponsorship: #{TREE_CEILING} unreadable: #{e.class}: #{e.message}"
    end

    def body_ignorable?(line)
      stripped = line.strip
      stripped.empty? || stripped.start_with?("#")
    end

    def source_path?(path)
      tree = TREES.find { |name| path.start_with?("#{name}/") }
      return false unless tree
      return false if path.match?(%r{/test/}) || path.match?(EXCLUDED_DIRS)

      SOURCE_EXTENSIONS.include?(File.extname(path).downcase)
    end

    def git_checkout?(root)
      _out, status = Master::Io::Exec.capture2e("git", "-C", root, "rev-parse", "--git-dir")
      status.success?
    end

    def tracked_paths(root)
      out, status = Master::Io::Exec.capture2e("git", "-C", root, "ls-files", "-z")
      raise "ratchet sponsorship: git ls-files failed: #{out}" unless status.success?

      out.split("\x00").reject(&:empty?).to_set
    end

    def diff_statuses(root, paths = [])
      out, status = Master::Io::Exec.capture2e("git", "-C", root, "diff", "--name-status", "HEAD", "--", *paths)
      return {} unless status.success?

      out.lines.each_with_object({}) do |line, result|
        state, path = line.chomp.split("\t", 2)
        next unless path

        result[path] = state
      end
    end
  end
end
