# frozen_string_literal: true

module Master
  module Review
    class CodeIndex
      # Read-only query surface over the built symbol/reference graph —
      # separated from CodeIndex's own build/reindex lifecycle.
      module QueryApi
        def size
          @lock.synchronize { @symbols.size }
        end

        def symbols_in(file)
          with_built_index do
            full = File.expand_path(file, @root)
            @symbols.values.select { |s| s.file == full }
          end
        end

        def find(name)
          with_built_index { find_locked(name) }
        end

        def references_to(fqn)
          with_built_index { references_for(fqn) }
        end

        def impact(fqn)
          with_built_index do
            refs = references_for(fqn)
            files = refs.map(&:from_file).uniq.map { |f| relativize(f) }
            callers = refs.map { |r| "#{relativize(r.from_file)}:#{r.from_line}" }.uniq
            { fqn:, reference_count: refs.size, files:, callers: }
          end
        end

        def summary(limit: nil)
          with_built_index do
            classes = summary_classes
            lib_count = @symbols.values.count { |s| s.file.include?("/lib/") }
            stamp = @built_at&.strftime("%H:%M") || "never"
            [
              "# Codebase: #{lib_count} lib symbols (indexed #{stamp})",
              "## Classes & Modules (#{classes.size})",
              *classes,
            ].join("\n")
          end
        end

        def query(name)
          with_built_index do
            hits = find_locked(name)
            next { error: "not found: #{name}" } if hits.empty?
            hits.map { |s| query_entry(s) }
          end
        end

        # Returns [file, line] for the first symbol matching name, or nil.
        def lookup(name)
          with_built_index do
            hit = find_locked(name).first
            hit ? [relativize(hit.file), hit.line] : nil
          end
        end
      end
    end
  end
end
