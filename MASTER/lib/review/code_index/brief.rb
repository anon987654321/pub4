# frozen_string_literal: true

module Master
  module Review
    class CodeIndex
      # The bounded view of the symbol graph that rides in every turn's system
      # prompt. The whole class listing of the repo ran to ~290 KB (~70K tokens)
      # on every model call, so the prompt now carries an orientation that is
      # small and constant, plus the slice of the graph the user's own words
      # name. The full detail stays one tool call away: symbol_lookup.
      module Brief
        SLICE_CAP_BYTES = 3_000
        SLICE_MAX_HITS = 24
        POINTER = "Ask for more with symbol_lookup(name:): definition, callers and impact for any class, module or method."

        # A CamelCase or qualified constant, or a backticked bare one. A plain
        # capitalised word ("Fix", "Master") opens sentences and would match
        # half the tree.
        CONSTANT = /\b[A-Z][a-z0-9]+(?:[A-Z][A-Za-z0-9]*)+(?:::[A-Z]\w*)*\b|\b[A-Z]\w*(?:::[A-Z]\w*)+\b|`([A-Z]\w*)`/
        PATH = %r{[\w./-]+\.rb\b}

        def summary(focus: nil)
          with_built_index do
            @orientation ||= build_orientation
            slice = focus_slice(focus.to_s)
            [@orientation, slice, POINTER].compact.join("\n")
          end
        end

        private

        def build_orientation
          classes = @symbols.values.select { |s| %i[class module].include?(s.type) }
          trees = classes.group_by { |s| relativize(s.file).split("/").first }
          counts = trees.map { |tree, syms| "#{tree} #{syms.size}" }.sort.join(", ")
          stamp = @built_at&.strftime("%H:%M") || "never"
          entries = %w[MASTER/bin/master MASTER/bin/operator].select { |e| File.exist?(File.join(@root, e)) }
          lines = ["# Codebase: #{@symbols.size} symbols, #{classes.size} classes and modules (indexed #{stamp})"]
          lines << "Classes and modules by tree: #{counts}"
          lines << "Entry points: #{entries.join(", ")}" if entries.any?
          lines.join("\n")
        end

        def focus_slice(text)
          return if text.empty?

          hits = named_symbols(text) | file_symbols(text)
          return if hits.empty?

          lines = hits.first(SLICE_MAX_HITS).map { |sym| format_summary_entry(sym) }
          lines << "  (+#{hits.size - SLICE_MAX_HITS} more)" if hits.size > SLICE_MAX_HITS
          body = +"## Named in this turn\n"
          lines.each do |line|
            break if body.bytesize + line.bytesize > SLICE_CAP_BYTES

            body << line << "\n"
          end
          body.chomp
        end

        def named_symbols(text)
          names = text.to_enum(:scan, CONSTANT).map { Regexp.last_match[1] || Regexp.last_match[0] }.uniq
          names.flat_map do |name|
            @symbols.values.select { |s| s.fqn == name || s.fqn.end_with?("::#{name}") }
          end.uniq.sort_by(&:fqn)
        end

        def file_symbols(text)
          text.scan(PATH).uniq.flat_map do |path|
            suffix = path.sub(%r{\A\./}, "")
            @symbols.values.select { |s| %i[class module].include?(s.type) && relativize(s.file).end_with?(suffix) }
          end.uniq.sort_by(&:fqn)
        end
      end
    end
  end
end
