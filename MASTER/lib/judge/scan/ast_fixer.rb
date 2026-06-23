# frozen_string_literal: true

require "prism"
require_relative "ast_fixer/web_transforms"

module Master
  module Judge
    module Scan
      # Architecture #4: deterministic AST-level autofixes for mechanical rules.
      # No LLM call, no token cost. Applied before LLM sweep on every scan cycle.
      # Each transform is idempotent — safe to apply repeatedly.
      class AstFixer
        FROZEN_HEADER = "# frozen_string_literal: true\n"
        BARE_RESCUE_RE = /^(\s*)rescue(\s*\n|\s*=>)/.freeze
        JS_EXTS = %w[.js .ts .jsx .tsx].freeze
        STYLE_EXTS = %w[.css .scss].freeze

        Result = Struct.new(:path, :changed, :transforms, keyword_init: true)
        Strategy = Struct.new(:predicate, :transforms, keyword_init: true)
        STRATEGIES = [
          Strategy.new(predicate: :ruby?, transforms: %i[add_frozen_header fix_bare_rescue freeze_mutable_constants]),
          Strategy.new(predicate: :sql_context?, transforms: %i[normalise_null_comparison]),
          Strategy.new(predicate: :shell?, transforms: %i[add_strict_mode]),
          Strategy.new(predicate: :html?, transforms: %i[add_html_lang add_meta_charset add_lazy_loading]),
          Strategy.new(predicate: :javascript?, transforms: %i[replace_unreassigned_var convert_for_in_arrays convert_string_concat convert_optional_chaining]),
          Strategy.new(predicate: :style?, transforms: %i[logical_properties])
        ].freeze
        UNIVERSAL_TRANSFORMS = %i[collapse_blank_lines strip_trailing_whitespace remove_immediate_dead_code add_trailing_commas].freeze

        include WebTransforms

        def self.fix(path, source, event_bus: nil)
          new(path, source, event_bus:).apply
        end

        def initialize(path, source, event_bus: nil)
          @path = path
          @source = source
          @bus = event_bus
          @transforms = []
        end

        def apply
          out = @source
          out = apply_strategies(out)
          changed = out != @source
          Result.new(path: @path, changed:, transforms: @transforms)
            .tap { publish_and_write(out) if changed }
        end

        private

        def apply_strategies(src)
          out = apply_transforms(src, UNIVERSAL_TRANSFORMS.first(2))
          applicable_strategies.each do |strategy|
            out = apply_transforms(out, strategy.transforms)
          end
          apply_transforms(out, UNIVERSAL_TRANSFORMS.drop(2))
        end

        def applicable_strategies
          STRATEGIES.select { |strategy| send(strategy.predicate) }
        end

        def apply_transforms(src, transforms)
          transforms.reduce(src) { |current, transform| send(transform, current) }
        end

        def publish_and_write(out)
          write_back(out)
          @bus&.publish("ast_fixer:transform", path: @path, transforms: @transforms)
        end

        def add_frozen_header(src)
          return src if src.start_with?(FROZEN_HEADER)

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

        def normalise_null_comparison(src)
          return src if @path.to_s.include?("/judge/scan/")

          changed = false
          out = src.gsub(/(?<![<>!])=\s*NULL\b/i) { changed = true; "IS NULL" }
                   .gsub(/!=\s*NULL\b/i) { changed = true; "IS NOT NULL" }
                   .gsub(/<>\s*NULL\b/i) { changed = true; "IS NOT NULL" }
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

        def collapse_blank_lines(src)
          out = src.gsub(/(\n\n)\n+/, "\\1")
          @transforms << :collapse_blank_lines if out != src
          out
        end

        def strip_trailing_whitespace(src)
          out = src.gsub(/[ \t]+(?=\n|\z)/, "")
          @transforms << :trailing_whitespace if out != src
          out
        end

        SINGLE_LINE_MUTABLE_CONST_RE = /
          ^\s*[A-Z][A-Z_]*\s*=\s*
          (?:
            [\[{][^\n]*[\]}]
            |%w\[[^\n]*\]
            |%i\[[^\n]*\]
          )
          (?<!\.freeze)\s*$
        /x.freeze

        def freeze_mutable_constants(src)
          changed = false
          out = src.lines.map do |line|
            next line unless line.match?(SINGLE_LINE_MUTABLE_CONST_RE)

            changed = true
            line.chomp.rstrip + ".freeze\n"
          end.join
          @transforms << :freeze_constants if changed
          out
        end

        STRICT_MODE = "set -euo pipefail\n"

        def add_strict_mode(src)
          return src if src.include?(STRICT_MODE) || src.include?("set -e")

          lines = src.lines
          shebang_idx = lines.index { |line| line.start_with?("#!") }
          return src unless shebang_idx

          lines.insert(shebang_idx + 1, STRICT_MODE)
          @transforms << :strict_mode
          lines.join
        end

        def remove_immediate_dead_code(src)
          lines = src.lines
          keep = []
          changed = false
          skip_next = false
          lines.each_with_index do |line, index|
            if skip_next && executable_line?(line)
              changed = true
              skip_next = false
              next
            end
            keep << line
            next_line = lines[index + 1].to_s
            skip_next = unconditional_terminal?(line) && skippable_dead_line?(next_line) && !open_collection?(line)
          end
          @transforms << :dead_code if changed
          keep.join
        end

        def open_collection?(line)
          counts = line.each_char.with_object(Hash.new(0)) { |ch, tally| tally[ch] += 1 if "(){}[]".include?(ch) }
          counts["("] > counts[")"] || counts["{"] > counts["}"] || counts["["] > counts["]"]
        end

        def unconditional_terminal?(line)
          stripped = line.strip
          return false unless stripped.match?(/\A(?:return|raise|exit|throw)\b/)
          return false if stripped.match?(/\b(?:if|unless)\s/)

          true
        end

        def skippable_dead_line?(line)
          stripped = line.strip
          return false if stripped.empty?
          return false if stripped.start_with?("#", "//")
          return false if stripped.match?(/\A(?:end|else|elsif|when|rescue|ensure)\b/)

          true
        end

        def executable_line?(line) = skippable_dead_line?(line)

        def add_trailing_commas(src)
          lines = src.lines
          changed = false
          (1...lines.length).each do |i|
            current = lines[i].strip
            previous = lines[i - 1]
            next unless current.match?(/^[\]}]/)
            next if block_close?(lines, i)
            next if percent_word_array_close?(lines, i)
            next if previous.rstrip.end_with?(",", "[", "{", "(")
            next unless previous.match?(/^\s*[^#\n]+/)

            lines[i - 1] = previous.rstrip + ",\n"
            changed = true
          end
          @transforms << :trailing_commas if changed
          lines.join
        end

        def block_close?(lines, close_index)
          depth = 0
          close_index.downto(0) do |index|
            line = lines[index]
            depth += line.count("}") - line.count("{")
            next unless depth.zero? && line.match?(/\{\s*\|/)

            return true
          end
          false
        end

        def percent_word_array_close?(lines, close_index)
          close_line = lines[close_index].strip
          return false unless close_line.start_with?("]")

          close_index.downto(0) do |index|
            return true if lines[index].match?(%r/%[iw]\[/)
            return false if lines[index].strip.start_with?("[", "{")
          end
          false
        end

        def ruby? = File.extname(@path).downcase == ".rb"

        def shell? = %w[.zsh .sh .bash].include?(File.extname(@path).downcase)

        def html? = %w[.html .erb .html.erb].any? { |ext| @path.to_s.downcase.end_with?(ext) }

        def javascript? = JS_EXTS.include?(File.extname(@path).downcase)

        def style? = STYLE_EXTS.include?(File.extname(@path).downcase)

        def sql_context?
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
