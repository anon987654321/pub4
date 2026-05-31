# frozen_string_literal: true

require "prism"

module Master
  module Judge
    module Scan
    # Architecture #4: deterministic AST-level autofixes for mechanical rules.
    # No LLM call, no token cost. Applied before LLM sweep on every scan cycle.
    # Each transform is idempotent — safe to apply repeatedly.
      class AstFixer
        FROZEN_HEADER = "# frozen_string_literal: true\n"
        BARE_RESCUE_RE = /^(\s*)rescue(\s*\n|\s*=>)/.freeze

        Result = Struct.new(:path, :changed, :transforms, keyword_init: true)

        # Apply all eligible fixes to +source+ for +path+.
        # Returns Result with :changed (bool) and :transforms (array of applied fix names).
        def self.fix(path, source)
          new(path, source).apply
        end

        def initialize(path, source)
          @path = path
          @source = source
          @transforms = []
        end

        def apply
          out = @source
          out = add_frozen_header(out)         if ruby?
          out = fix_bare_rescue(out)           if ruby?
          out = normalise_null_comparison(out) if sql_in_ruby?
          out = collapse_blank_lines(out)
          out = strip_trailing_whitespace(out)
          out = freeze_mutable_constants(out)  if ruby?
          out = add_strict_mode(out)           if shell?
          changed = out != @source
          Result.new(path: @path, changed: changed, transforms: @transforms)
            .tap { write_back(out) if changed }
        end

        private

        # Add frozen_string_literal comment if absent.
        def add_frozen_header(src)
          return src if src.start_with?(FROZEN_HEADER)
          # Preserve shebang if present.
          if src.start_with?("#!")
            lines = src.lines
            lines.insert(1, FROZEN_HEADER)
            @transforms << :frozen_string_literal
            lines.join
          else
            @transforms << :frozen_string_literal
            FROZEN_HEADER + "\n" + src.lstrip
          end
        end

        # Replace bare `rescue` with `rescue StandardError`.
        # Only fires when Prism confirms the rescue is genuinely bare (no class listed).
        def fix_bare_rescue(src)
          result = Prism.parse(src)
          return src unless result.success?

          bare_lines = bare_rescue_lines(result.value)
          return src if bare_lines.empty?

          lines = src.lines
          bare_lines.each do |lineno|
            line_index = lineno - 1
            next unless line_index < lines.size
            lines[line_index] = lines[line_index].sub(/\brescue\b(?!\s+\w)/, "rescue StandardError")
          end
          @transforms << :bare_rescue
          lines.join
        end

        # `= NULL` → `IS NULL`, `!= NULL` → `IS NOT NULL` inside SQL heredocs/strings.
        # Skip scanner files — they carry `= NULL` literals inside detector regexes.
        def normalise_null_comparison(src)
          return src if @path.to_s.include?("/judge/scan/")
          changed = false
          out = src.gsub(/(?<![<>!])=\s*NULL\b/i) { changed = true; "IS NULL" }
                   .gsub(/!=\s*NULL\b/i)           { changed = true; "IS NOT NULL" }
                   .gsub(/<>\s*NULL\b/i)            { changed = true; "IS NOT NULL" }
          @transforms << :null_comparison if changed
          out
        end

        def bare_rescue_lines(node, lines = [])
          return lines unless node.is_a?(Prism::Node)
          if node.is_a?(Prism::RescueNode) && (node.exceptions.nil? || node.exceptions.empty?)
            lines << node.location.start_line
          end
          node.child_nodes.compact.each { |child| bare_rescue_lines(child, lines) }
          lines
        end

      # C01 — collapse 3+ consecutive blank lines to 2 (SQUINT_TEST).
        def collapse_blank_lines(src)
          out = src.gsub(/(\n\n)\n+/, "\\1")
          @transforms << :collapse_blank_lines if out != src
          out
        end

      # C02 — strip trailing whitespace from every line (TRAILING_WHITESPACE).
        def strip_trailing_whitespace(src)
          out = src.gsub(/[ \t]+(?=\n|\z)/, "")
          @transforms << :trailing_whitespace if out != src
          out
        end

      # C03 — append .freeze to mutable top-level constants (IMMUTABLE).
        MUTABLE_CONST_RE = /^(\s*[A-Z][A-Z_]*\s*=\s*[\[{])(.*)(?<!\.freeze)\s*$/.freeze

        def freeze_mutable_constants(src)
          lines = src.lines
          changed = false
          out = lines.map do |line|
            next line unless line.match?(MUTABLE_CONST_RE)
            next line if line.match?(/\.freeze\s*$/)
            next line if line.strip.end_with?(",", "(", "\\")
            changed = true
            line.chomp.rstrip + ".freeze\n"
          end.join
          @transforms << :freeze_constants if changed
          out
        end

      # C04 — add set -euo pipefail after shebang in shell scripts (STRICT_MODE_ZSH).
        STRICT_MODE = "set -euo pipefail\n"

        def add_strict_mode(src)
          return src if src.include?(STRICT_MODE) || src.include?("set -e")
          lines = src.lines
          shebang_idx = lines.index { |l| l.start_with?("#!") }
          return src unless shebang_idx
          lines.insert(shebang_idx + 1, STRICT_MODE)
          @transforms << :strict_mode
          lines.join
        end

        def ruby? = File.extname(@path).downcase == ".rb"

        def shell? = %w[.zsh .sh .bash].include?(File.extname(@path).downcase)

        def sql_in_ruby?
          ruby? || %w[.sql .erb].include?(File.extname(@path).downcase)
        end

        def write_back(content)
          temporary_path = "#{@path}.ast_fix.#{Process.pid}.tmp"
          File.write(temporary_path, content, encoding: "UTF-8")
          File.rename(temporary_path, @path)
        rescue StandardError => e
          File.delete(temporary_path) if defined?(temporary_path) && File.exist?(temporary_path) rescue nil
          raise e
        end
      end
    end
  end
end
