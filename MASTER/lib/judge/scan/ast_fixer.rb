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

        MUTABLE_CONST_RE = /^(\s*[A-Z][A-Z_]*\s*=\s*[\[{])(.*)(?<!\.freeze)\s*$/.freeze

        def freeze_mutable_constants(src)
          changed = false
          out = src.lines.map do |line|
            next line unless line.match?(MUTABLE_CONST_RE)
            next line if line.match?(/\.freeze\s*$/)
            next line if line.strip.end_with?(",", "(", "\\")

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

        def add_html_lang(src)
          return src if src.match?(/<html\b[^>]*\blang=/)

          out = src.sub(/<html\b(?=[^>]*>)/) { |match| match.rstrip + ' lang="en"' }
          @transforms << :html_lang if out != src
          out
        end

        def add_lazy_loading(src)
          out = src.gsub(/<img\b(?=[^>]*>)(?![^>]*\bloading=)/) { |match| match.rstrip + ' loading="lazy"' }
          @transforms << :lazy_images if out != src
          out
        end

        def add_meta_charset(src)
          return src if src.match?(/<meta\s[^>]*charset=/i)

          out = src.sub(/<head\b[^>]*>/, "\\0\n<meta charset=\"UTF-8\">")
          @transforms << :meta_charset if out != src
          out
        end

        def replace_unreassigned_var(src)
          declared = src.scan(/\bvar\s+([A-Za-z_$][\w$]*)\b/).flatten
          reassigned = declared.select { |name| src.match?(/(?<!\bvar\s)(?<!\bconst\s)(?<!\blet\s)\b#{Regexp.escape(name)}\s*=(?!=)/) }
          out = src.gsub(/\bvar\s+([A-Za-z_$][\w$]*)/) do |match|
            reassigned.include?(Regexp.last_match(1)) ? match : match.sub("var", "const")
          end
          @transforms << :no_var if out != src
          out
        end

        def convert_for_in_arrays(src)
          changed = false
          out = src.gsub(/for\s*\(\s*const\s+([A-Za-z_$][\w$]*)\s+in\s+([A-Za-z_$][\w$]*(?:List|Array|Arr|s))\s*\)/) do
            changed = true
            "for (const #{Regexp.last_match(1)} of #{Regexp.last_match(2)})"
          end
          @transforms << :for_of if changed
          out
        end

        def convert_string_concat(src)
          changed = false
          out = src.gsub(/(['"])([^'"`\n]*)\1\s*\+\s*([A-Za-z_$][\w$]*(?:\.[A-Za-z_$][\w$]*)?)\s*\+\s*(['"])([^'"`\n]*)\4/) do
            changed = true
            "`#{Regexp.last_match(2)}${#{Regexp.last_match(3)}}#{Regexp.last_match(5)}`"
          end
          @transforms << :template_literals if changed
          out
        end

        def convert_optional_chaining(src)
          changed = false
          out = src.gsub(/\b([A-Za-z_$][\w$]*)\s*&&\s*\1\.([A-Za-z_$][\w$]*)\b/) do
            changed = true
            "#{Regexp.last_match(1)}?.#{Regexp.last_match(2)}"
          end
          @transforms << :optional_chaining if changed
          out
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
            skip_next = line.match?(/^\s*(return|raise|exit|throw)\b/) && executable_line?(lines[index + 1].to_s)
          end
          @transforms << :dead_code if changed
          keep.join
        end

        def executable_line?(line)
          stripped = line.strip
          !stripped.empty? && !stripped.start_with?("#", "//")
        end

        def add_trailing_commas(src)
          lines = src.lines
          changed = false
          (1...lines.length).each do |i|
            current = lines[i].strip
            previous = lines[i - 1]
            next unless current.match?(/^[\]}]/)
            next if previous.rstrip.end_with?(",", "[", "{", "(")
            next unless previous.match?(/^\s*[^#\n]+/)

            lines[i - 1] = previous.rstrip + ",\n"
            changed = true
          end
          @transforms << :trailing_commas if changed
          lines.join
        end

        def logical_properties(src)
          changed = false
          replacements = {
            "margin-left" => "margin-inline-start",
            "margin-right" => "margin-inline-end",
            "padding-left" => "padding-inline-start",
            "padding-right" => "padding-inline-end",
            "border-left" => "border-inline-start",
            "border-right" => "border-inline-end"
          }
          out = src.gsub(/\b(?:#{replacements.keys.map { |key| Regexp.escape(key) }.join("|")})\s*:/) do |match|
            changed = true
            match.sub(match.split(":").first, replacements.fetch(match.split(":").first))
          end
          @transforms << :logical_properties if changed
          out
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
