# frozen_string_literal: true

require "digest"
require "time"

module Master
  module AI
    # The compact orientation frame every model turn receives before it touches
    # project source. It is a view, not a second constitution: paths and values
    # are read from the live tree and durable state, while OperatorContract owns
    # the behavioral law.
    module Orientation
      VERSION = 1
      DEFAULT_DEPTH = 2
      MAX_ENTRIES = 80
      SKIP = %w[.git .bundle vendor node_modules tmp log coverage storage .master knowledge output sockets pids cache].freeze

      module_function

      def render(root:, target: nil, depth: DEFAULT_DEPTH, max_entries: MAX_ENTRIES)
        root = File.realpath(root)
        repo_root = File.basename(root) == "MASTER" ? File.expand_path("..", root) : root
        parts = [
          "MASTER orientation v#{VERSION}",
          "repo: #{repo_root}",
          "target: #{target ? relative(target, repo_root) : relative(root, repo_root)}",
          "contract: orient → inspect → act → verify",
          "verification: evidence before completion",
          "trees: MASTER, RAILS, OPENBSD; STUDIO = MASTER/tools",
          "head: #{git_head(repo_root)}",
          "docs: #{key_docs(repo_root).join(", ")}",
        ]

        plan = active_plan(root)
        parts << "active plan: #{compact(plan)}" unless plan.to_s.empty?

        wishes = pending_wishes(root)
        parts << "pending wishes: #{wishes.join(", ")}" unless wishes.empty?

        parts << "tree:"
        parts.concat(tree_lines(root, depth:, max_entries:))
        parts.join("\n")
      rescue StandardError => e
        "MASTER orientation unavailable: #{e.class}: #{e.message}"
      end

      def tree_lines(root, depth:, max_entries:)
        seen = 0
        truncated = false
        lines = []

        walk = lambda do |dir, indent, level|
          return if level > depth || truncated

          Dir.children(dir).sort_by do |name|
            path = File.join(dir, name)
            [File.directory?(path) ? 0 : 1, name]
          end.each do |name|
            break if seen >= max_entries

            next if SKIP.include?(name)

            path = File.join(dir, name)
            seen += 1
            lines << "#{indent}#{name}#{File.directory?(path) ? "/" : ""}"
            walk.call(path, "#{indent}  ", level + 1) if File.directory?(path)
          end

          truncated = true if seen >= max_entries
        end

        lines << "#{File.basename(root)}/"
        walk.call(root, "", 0)
        lines << "... (orientation tree truncated)" if truncated
        lines
      end

      def active_plan(root)
        path = File.join(root, "runtime", "active_plan.md")
        return unless File.file?(path)

        File.read(path, encoding: "UTF-8")[0, 900].strip
      end

      def pending_wishes(root)
        path = File.join(root, "runtime", "wishlist.md")
        return [] unless File.file?(path)

        File.readlines(path, encoding: "UTF-8", chomp: true)
            .grep(/\A###? \d+\./)
            .first(5)
            .map { |line| line.sub(/\A###? /, "").strip }
      end

      def key_docs(repo_root)
        %w[CLAUDE.md TREE.md TODO.md].select { |name| File.file?(File.join(repo_root, name)) }
      end

      def git_head(repo_root)
        git = File.join(repo_root, ".git")
        head = if File.file?(git)
          git_dir = File.read(git).strip.sub(/\Agitdir:\s*/, "")
          File.read(File.expand_path("HEAD", File.join(File.dirname(git), git_dir)))
        elsif File.directory?(git)
          File.read(File.join(git, "HEAD"))
        end
        head.to_s.strip.delete_prefix("ref: ").split("/").last || "unknown"
      rescue StandardError
        "unknown"
      end

      def relative(path, repo_root)
        full = File.expand_path(path)
        return "." if full == repo_root
        return path.to_s unless full.start_with?("#{repo_root}/")

        full.delete_prefix("#{repo_root}/")
      end

      def compact(text, limit = 500)
        body = text.to_s.gsub(/\s+/, " ").strip
        body.length > limit ? "#{body[0, limit - 1]}…" : body
      end

      def digest(root:)
        Digest::SHA256.hexdigest(render(root:))[0, 16]
      end
    end
  end
end
