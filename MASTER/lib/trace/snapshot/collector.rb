# frozen_string_literal: true

require "open3"

require "set"
require "shellwords"

module Master
  module Trace
    module Snapshot
      # Shared snapshot policy: git-tracked source text only, with explicit path skips.
      # Used by Snapshot::Publisher (/snapshot). The repo-root packs are
      # `pub4 snapshot`, which walks git ls-files itself rather than through here.
      module Collector
        SKIP_SEGS = %w[
          .git .master vendor tmp var node_modules .bundle coverage log dist knowledge
          runtime .venv renders storage quarantine .cache
        ].freeze

        TEXT_EXTS = %w[
          .rb .rake .ru .py .js .mjs .ts .jsx .tsx .css .scss .html .erb .haml .slim
          .zsh .sh .bash .md .markdown .yml .yaml .json .toml .gemspec .txt .conf
          .ini .env .sql .xml .svg .ruby-version .gitignore .keep
        ].freeze.to_set

        TEXT_NAMES = %w[Gemfile Rakefile Dockerfile Makefile Procfile].to_set.freeze
        MAX_INLINE_BYTES = 262_144
        GIT_LABELS = %w[MASTER OPERATOR RAILS OPENBSD].freeze
        DEPLOY_PILLARS = %w[OPERATOR RAILS OPENBSD].freeze

        POLICY_SUMMARY =
          "git-tracked source text only (skips vendor, node_modules, tmp, knowledge, runtime, " \
          ".venv, renders, storage; files over #{MAX_INLINE_BYTES / 1024} KB listed, not inlined)".freeze

        module_function

        def skip_path?(rel)
          rel.split("/").any? { |segment| segment == "." || segment == ".." || SKIP_SEGS.include?(segment) }
        end

        def text_file?(path)
          TEXT_EXTS.include?(File.extname(path).downcase) || TEXT_NAMES.include?(File.basename(path))
        end

        def collect_paths(label:, repo_root:, target:)
          label_key = label.to_s.upcase
          if git_repo?(repo_root) && GIT_LABELS.include?(label_key)
            return deploy_pillar_paths(repo_root) if label_key == "OPENBSD"

            git_tracked_paths(repo_root, label_key)
          else
            tree_paths(target)
          end
        end

        # cap: nil disables the size cap entirely -- every text file is inlined
        # in full, no matter how large. Nothing passes it: Snapshot::Publisher is
        # the only caller and keeps the default, because its boot-context digest
        # is meant to stay small. The uncapped full-repo pack is `pub4 snapshot`,
        # which walks git ls-files itself rather than through here.
        def partition(paths, cap: MAX_INLINE_BYTES)
          text = paths.select { |path| File.file?(path) && text_file?(path) }
          return { inlined: text.sort, large: [] } if cap.nil?

          {
            inlined: text.select { |path| File.size(path) <= cap }.sort,
            large: text.select { |path| File.size(path) > cap }.sort,
          }
        end

        def file_section(path, cap: MAX_INLINE_BYTES)
          size = File.size(path)
          return [["_binary: #{size} bytes (not inlined)_"], 0] unless text_file?(path)
          return [["_text: #{size} bytes over #{cap} cap (not inlined)_"], 0] if cap && size > cap

          text = File.read(path, encoding: "UTF-8", invalid: :replace)
          lang = Master::FILE_LANGUAGE_MAP.fetch(File.extname(path).downcase, "text")
          lines = text.each_line.map(&:rstrip)
          [["```#{lang}", *lines, "```"], lines.size]
        rescue StandardError => e
          [["```text", "[unreadable: #{e.message}]", "```"], 1]
        end

        def git_repo?(repo_root)
          File.directory?(File.join(repo_root, ".git"))
        end

        def deploy_pillar_paths(repo_root)
          DEPLOY_PILLARS.flat_map { |pillar| git_tracked_paths(repo_root, pillar) }.uniq.sort
        end

        def git_tracked_paths(repo_root, label)
          # The arg-array form: nothing is parsed by a shell, so nothing needs
          # escaping — the escape-then-join spelling was the veto's shape anyway.
          out, status = Open3.capture2("git", "-C", repo_root, "ls-files", label, err: File::NULL)
          return [] unless status.success?

          out.lines.map(&:chomp).reject(&:empty?).filter_map do |rel|
            next if skip_path?(rel)

            abs = File.join(repo_root, rel)
            abs if File.file?(abs)
          end.sort
        end

        def tree_paths(target)
          Dir.glob(File.join(target, "**", "*"), File::FNM_DOTMATCH)
             .reject { |path| skip_path?(path.delete_prefix("#{target}/").delete_prefix("/")) }
             .select { |path| File.file?(path) }
             .sort
        end
      end
    end
  end
end
