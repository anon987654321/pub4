# frozen_string_literal: true

module Master
  module Review
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
              /(<meta\s[^>]*name=["']viewport["'][^>]*content=["'])([^"']*)(["'])/i,
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
              next match if comment_context?(Regexp.last_match)

              reassigned.include?(Regexp.last_match(1)) ? match : match.sub("var", "const")
            end
            @transforms << :no_var if out != src
            out
          end

          # Prose about code contains code. These transforms read raw source, so
          # a JSDoc line quoting `'online' + SW` is a concat chain to
          # CONCAT_CHAIN, and converting it rewrites documentation
          # (web/public/offline_memory.js). A comment cannot need a code fix:
          # decline any match whose line is a `//` comment, a block-comment
          # opener, a `*` continuation, or sits after a whitespace-preceded `//`
          # — the whitespace requirement keeps `http://` inside string URLs
          # convertible.
          def comment_context?(md)
            pre = md.pre_match
            line = pre[(pre.rindex("\n") || -1) + 1..]
            line.match?(%r{\A\s*(?:\*|/\*)}) || line.match?(%r{(?:\A|\s)//})
          end

          # for-in yields KEYS, for-of yields VALUES, so this rewrite is only
          # sound when the body never uses the loop variable to index the
          # collection -- `for (const k in xs) use(xs[k])` becomes
          # `use(xs[xs[0]])` under for-of. The old form only matched `const`,
          # which hid the hazard rather than avoiding it: the same body written
          # with `let` was left alone by accident, not by design. Accept all
          # three declaration keywords and check the body instead.
          FOR_IN_HEAD = /for\s*\(\s*(?:const|let|var)\s+([A-Za-z_$][\w$]*)\s+in\s+([A-Za-z_$][\w$]*(?:List|Array|Arr|s))\s*\)/
          private_constant :FOR_IN_HEAD

          def convert_for_in_arrays(src)
            changed = false
            out = src.gsub(FOR_IN_HEAD) do |match|
              next match if comment_context?(Regexp.last_match)

              variable = Regexp.last_match(1)
              collection = Regexp.last_match(2)
              next match if indexes_collection?(src, collection:, variable:)

              changed = true
              "for (const #{variable} of #{collection})"
            end
            @transforms << :for_of if changed
            out
          end

          def indexes_collection?(source, collection:, variable:)
            source.match?(/\b#{Regexp.escape(collection)}\s*\[\s*#{Regexp.escape(variable)}\s*\]/)
          end

          # A concatenation is a chain, not a triple. The old pattern required
          # exactly literal + identifier + literal, so `base + "/path/" + id`
          # (identifier first) and any chain longer than three parts were left
          # alone. Match the whole run of `+`-joined literals and identifier
          # paths instead, and convert when at least one part is a literal and
          # one is an interpolation -- a chain of pure literals is concatenation
          # the parser folds anyway, and a chain of pure identifiers is
          # arithmetic as far as this transform can tell.
          # No backreference for the quote: CONCAT_PART is interpolated into
          # CONCAT_CHAIN more than once, and a `\1` inside it would renumber to
          # the combined pattern's first group -- so a chain whose first part is
          # an identifier left that group unset and the whole-chain match failed,
          # silently falling back to the longest trailing sub-chain.
          CONCAT_PART = /(?:'[^'`\\\n]*'|"[^"`\\\n]*"|[A-Za-z_$][\w$]*(?:\.[A-Za-z_$][\w$]*)*)/
          CONCAT_CHAIN = /#{CONCAT_PART}(?:\s*\+\s*#{CONCAT_PART}){1,}/
          private_constant :CONCAT_PART, :CONCAT_CHAIN

          # CONCAT_PART matches a dotted identifier path and stops at `(`, so a
          # chain ending in a *call* matched only the callee and left the
          # argument list dangling:
          #
          #   ' — *cough* — ' + text.slice(cut + 1)
          #     -> ` — *cough* — ${text.slice}`(cut + 1)
          #
          # which is a template literal invoked as a function — a TypeError on
          # every execution, and valid syntax, so it passes `node --check` and
          # every parser gate. This shipped four times in `e7e48eed1` across
          # web/public/chat.js and face_speech_runtime.js and sat in the tree
          # until a rebuild surfaced it.
          #
          # The transform cannot absorb a call expression, so it declines rather
          # than converting half of one. Same guard covers a call mid-chain
          # (`"a" + f(x) + "b"` matches up to `f`, and post_match starts `(`).
          def convert_string_concat(src)
            changed = false
            out = src.gsub(CONCAT_CHAIN) do |match|
              next match if comment_context?(Regexp.last_match)
              next match if Regexp.last_match.post_match.start_with?("(")

              literal = template_literal_for(match)
              next match unless literal

              changed = true
              literal
            end
            @transforms << :template_literals if changed
            out
          end

          def template_literal_for(chain)
            parts = chain.split(/\s*\+\s*/)
            return nil unless parts.size > 1

            literals, expressions = parts.partition { |part| part.match?(/\A(['"]).*\1\z/m) }
            return nil if literals.empty? || expressions.empty?
            return nil if literals.any? { |part| part.include?("`") || part.include?("${") }

            body = parts.map do |part|
              literals.include?(part) ? part[1..-2] : "${#{part}}"
            end.join
            "`#{body}`"
          end

          # `a && a.b && a.b.c` used to convert its first link and then stop
          # forever: the backreference only matched a bare identifier, so once
          # the head became `a?.b` no later pass could see it as the base of the
          # next link. The rule kept firing on the tail of every chain it had
          # already "fixed". Match a dotted base, compare it to the next term
          # with the optional markers normalised away, and iterate to a fixed
          # point so one call converts the whole chain.
          OPTIONAL_LINK = /([A-Za-z_$][\w$]*(?:\??\.[A-Za-z_$][\w$]*)*)\s*&&\s*([A-Za-z_$][\w$]*(?:\.[A-Za-z_$][\w$]*)*)\.([A-Za-z_$][\w$]*)\b/
          MAX_CHAIN_PASSES = 16
          private_constant :OPTIONAL_LINK, :MAX_CHAIN_PASSES

          def convert_optional_chaining(src)
            out = src
            MAX_CHAIN_PASSES.times do
              pass = link_optional_chain(out)
              break if pass == out

              out = pass
            end
            @transforms << :optional_chaining if out != src
            out
          end

          def link_optional_chain(src)
            src.gsub(OPTIONAL_LINK) do |match|
              next match if comment_context?(Regexp.last_match)

              base = Regexp.last_match(1)
              guarded = Regexp.last_match(2)
              property = Regexp.last_match(3)
              next match unless base.gsub("?.", ".") == guarded

              "#{base}?.#{property}"
            end
          end

          def logical_properties(src)
            changed = false
            replacements = {
              "margin-left" => "margin-inline-start",
              "margin-right" => "margin-inline-end",
              "padding-left" => "padding-inline-start",
              "padding-right" => "padding-inline-end",
              "border-left" => "border-inline-start",
              "border-right" => "border-inline-end",
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
