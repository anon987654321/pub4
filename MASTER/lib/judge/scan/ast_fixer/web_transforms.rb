# frozen_string_literal: true

module Master
  module Judge
    module Scan
      class AstFixer
        module WebTransforms
          private

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

          def add_viewport_fit(src)
            return src unless src.match?(/name=["']viewport["']/i)
            return src if src.match?(/viewport-fit\s*=\s*cover/i)

            out = src.gsub(
              /(<meta\s[^>]*name=["']viewport["'][^>]*content=["'])([^"']*)(["'])/i
            ) do
              content = Regexp.last_match(2)
              next Regexp.last_match(0) if content.match?(/viewport-fit\s*=\s*cover/i)

              separator = content.include?(",") ? ", " : ", "
              "#{Regexp.last_match(1)}#{content}#{separator}viewport-fit=cover#{Regexp.last_match(3)}"
            end
            @transforms << :viewport_fit if out != src
            out
          end

          def add_skip_to_main(src)
            return src unless layout_file?
            return src if src.match?(/skip|#main-content/i)

            out = src
            unless out.match?(/skip-link|href=["']#main-content/i)
              out = out.sub(/<body\b[^>]*>/i) { |match| "#{match}\n  <a class=\"skip-link\" href=\"#main-content\">Skip to main content</a>" }
            end
            unless out.match?(/id=["']main-content["']/i)
              out = out.sub(/<main\b(?![^>]*\bid=)/i) { |match| match.sub("<main", '<main id="main-content"') }
            end
            @transforms << :skip_to_main if out != src
            out
          end

          def layout_file? = @path.to_s.include?("/app/views/layouts/")

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
        end
      end
    end
  end
end
