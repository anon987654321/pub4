# frozen_string_literal: true

module Master
  module Ground
    module Orders
      # After every source write, emit merge/rename targets — OpenBSD-flat, dense parameterized slugs.
      class AggressiveMerge < Base
        THIN_LINES = 45
        MAX_LIB_DEPTH = 4

        def call
          paths = mutation_paths
          candidates = paths.flat_map { |path| candidates_for(path) }
                            .uniq { |row| "#{row[:action]}:#{row[:from]}:#{row[:to]}" }
          candidates.each { |row| bus&.publish("aggressive_merge:candidate", **row) }
          bus&.publish("aggressive_merge:scan", count: candidates.size, paths: paths.size)
          Result.ok(candidates:, paths:)
        rescue StandardError => e
          Result.err(e.message)
        end

        private

        def mutation_paths
          tracker = Master::Trace::WriteTracker.current
          touched = Array(tracker&.paths).map { |path| expand_path(path) }.reject(&:empty?).uniq
          return touched if touched.any?

          event_path = @container[:event]&.dig(:path).to_s
          expanded = expand_path(event_path)
          if !expanded.empty? && File.exist?(expanded)
            return [expanded]
          elsif !expanded.empty?
            parent = File.dirname(expanded)
            return [parent] if File.directory?(parent)
          end

          lib = File.join(root, "lib")
          File.directory?(lib) ? [lib] : [root]
        end

        def expand_path(path)
          value = path.to_s.strip
          return "" if value.empty?

          full = File.expand_path(value, root)
          full.start_with?("#{root}/") ? full : ""
        rescue StandardError
          ""
        end

        def candidates_for(path)
          full = expand_path(path)
          return [] if full.empty?

          if File.file?(full)
            file_candidates(full) + directory_candidates(File.dirname(full))
          elsif File.directory?(full)
            directory_candidates(full)
          else
            []
          end
        end

        def file_candidates(path)
          rel = rel_path(path)
          return [] unless rel.end_with?(".rb")

          out = slug_candidates(rel, File.basename(path, ".rb"))
          lines = File.foreach(path).count
          if lines.positive? && lines <= THIN_LINES
            target = fold_target_for(path)
            out << action(:merge, rel, target, "thin file (#{lines} lines) — fold into parent") if target
          end

          if rel.start_with?("lib/") && rel.count("/") > MAX_LIB_DEPTH
            out << action(:flatten, rel, shallow_target(rel), "depth #{rel.count('/')} > #{MAX_LIB_DEPTH} — flatten toward lib/")
          end
          out.uniq { |row| "#{row[:action]}:#{row[:from]}:#{row[:to]}" }
        rescue StandardError => e
          Master::Ground::Swallow.log(e, context: "AggressiveMerge.file_candidates")
          []
        end

        def slug_candidates(rel, stem)
          ParameterizedSlug.issues_for_stem(stem).map do |issue|
            to_rel = issue.to == issue.from ? rel : rel.sub(/[^\/]+\.rb\z/, "#{issue.to}.rb")
            action(issue.action.to_sym, rel, to_rel, issue.reason)
          end
        end

        def directory_candidates(dir)
          return [] unless File.directory?(dir)

          Dir.glob(File.join(dir, "*.rb")).flat_map { |file| file_candidates(file) }
        end

        def fold_target_for(path)
          dir = File.dirname(path)
          stem = File.basename(path, ".rb")
          return if ParameterizedSlug.fold_suffix?(stem)

          siblings = Dir.glob(File.join(dir, "*.rb")).reject { |entry| entry == path }
          parent = siblings.find { |entry| File.basename(entry, ".rb") == stem.split("_").first }
          rel_path(parent) if parent
        end

        def shallow_target(rel)
          parts = rel.split("/")
          return rel if parts.size <= MAX_LIB_DEPTH + 1

          ["lib", parts[-2], parts[-1]].join("/")
        end

        def action(kind, from, to, reason)
          { action: kind.to_s, from: from.to_s, to: to.to_s, reason: reason.to_s }
        end

        def rel_path(path)
          path.delete_prefix("#{root}/")
        end
      end
    end
  end
end
