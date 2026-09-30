# frozen_string_literal: true

require "open3"
require "set"

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

      additions, deletions = source_population_delta(root, paths)
      body_delta = master_lib_body_delta(root)

      return true if additions.zero? && deletions.zero? && body_delta.zero?
      return true if paths.include?(TREE_CEILING)

      raise "ratchet sponsorship required: #{TREE_CEILING} must change with source growth/deletion " \
            "(files +#{additions}/-#{deletions}, MASTER/lib body #{format("%+d", body_delta)} lines)"
    end

    def source_population_delta(root, paths)
      tracked = tracked_paths(root)
      statuses = diff_statuses(root)
      additions = statuses.count { |path, state| source_path?(path) && state.start_with?("A") }
      deletions = statuses.count { |path, state| source_path?(path) && state.start_with?("D") }

      additions += paths.count do |path|
        source_path?(path) && !tracked.include?(path) && !statuses.key?(path)
      end
      deletions += paths.count do |path|
        source_path?(path) && tracked.include?(path) &&
          !File.exist?(File.join(root, path)) && !statuses.key?(path)
      end

      [additions, deletions]
    end

    def master_lib_body_delta(root)
      out, status = Open3.capture2e("git", "-C", root, "diff", "--unified=0", "HEAD", "--", "MASTER/lib")
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
      added - deleted
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
      _out, status = Open3.capture2e("git", "-C", root, "rev-parse", "--git-dir")
      status.success?
    end

    def tracked_paths(root)
      out, status = Open3.capture2e("git", "-C", root, "ls-files", "-z")
      raise "ratchet sponsorship: git ls-files failed: #{out}" unless status.success?

      out.split("\x00").reject(&:empty?).to_set
    end

    def diff_statuses(root)
      out, status = Open3.capture2e("git", "-C", root, "diff", "--name-status", "HEAD")
      return {} unless status.success?

      out.lines.each_with_object({}) do |line, result|
        state, path = line.chomp.split("\t", 2)
        next unless path

        result[path] = state
      end
    end
  end
end
