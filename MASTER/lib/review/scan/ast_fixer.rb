# frozen_string_literal: true

require "prism"
require "set"
require_relative "ast_fixer/syntax_transforms"
require_relative "ast_fixer/web_transforms"
require_relative "ast_fixer/dead_code_and_commas"

module Master
  module Review
    module Scan
      # Architecture #4: deterministic AST-level autofixes for mechanical rules.
      # No LLM call, no token cost. Applied before LLM sweep on every scan cycle.
      # Each transform is idempotent — safe to apply repeatedly.
      #
      # This class is dispatch plus the four whitespace transforms that need no
      # knowledge of the source at all: pick the strategies whose predicate
      # matches the path, run their transforms in order, refuse any transform
      # that turns parseable Ruby into unparseable Ruby, write back. Everything
      # that has to know something — the language's syntax, HTML/JS/CSS, or
      # which lines sit inside multi-line literals — lives in a mixin.
      class AstFixer
        JS_EXTS = %w[.js .ts .jsx .tsx].freeze
        STYLE_EXTS = %w[.css .scss].freeze

        Result = Struct.new(:path, :changed, :transforms, keyword_init: true)
        Strategy = Struct.new(:predicate, :transforms, keyword_init: true)
        STRATEGIES = [
          Strategy.new(predicate: :ruby?, transforms: %i[add_frozen_header fix_bare_rescue freeze_mutable_constants remove_immediate_dead_code add_trailing_commas]),
          Strategy.new(predicate: :sql_context?, transforms: %i[normalise_null_comparison]),
          Strategy.new(predicate: :shell?, transforms: %i[add_strict_mode]),
          Strategy.new(predicate: :html?, transforms: %i[add_html_lang add_meta_charset add_viewport_fit add_skip_to_main add_lazy_loading]),
          Strategy.new(predicate: :javascript?, transforms: %i[replace_unreassigned_var convert_for_in_arrays convert_string_concat convert_optional_chaining]),
          Strategy.new(predicate: :style?, transforms: %i[logical_properties]),
        ].freeze
        # remove_immediate_dead_code/add_trailing_commas are Ruby-AST heuristics
        # (Prism-based literal-line protection, Ruby hash/array trailing-comma
        # convention) -- they used to sit here and run against every file type.
        # On non-Ruby source, Prism.parse fails, literal_lines comes back empty,
        # the heuristics run fully unguarded, AND apply_transforms's own
        # parses?-before/after safety net only fires `if ruby?` -- so a broken
        # transform on a .js/.css file had zero backstop. Confirmed in production:
        # add_trailing_commas turned every CSS rule's closing `}` into a trailing
        # `,` (e.g. `--z-skip: 2000;` + `}` -> `--z-skip: 2000;,`), and
        # remove_immediate_dead_code deleted live sibling if-branches in chat.js
        # that only *looked* unreachable without real block-scope analysis.
        # Now Ruby-only, via the ruby? strategy above.
        UNIVERSAL_TRANSFORMS = %i[expand_tabs collapse_blank_lines strip_trailing_whitespace ensure_final_newline].freeze

        include SyntaxTransforms
        include WebTransforms
        include DeadCodeAndCommas

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

        # An explicit accumulator loop, deliberately — not reduce, not
        # each_with_object.
        #
        # The accumulator is the rewritten source, so each step must produce the
        # next value. each_with_object returns the object and throws the block
        # result away, which turns every transform into a no-op; all thirteen
        # transform tests fail at once and nothing else does.
        #
        # It has been written as `reduce(src)` and rewritten to
        # `each_with_object(src)` twice, by the LLM fix sweep applying rule
        # EACH_WITH_OBJECT (data/rules/line.yml). That rule's lexical detector
        # requires `reduce({})` — a fresh empty hash — and never matched this
        # line; the sweep applied it from the rule's *name* instead. Fixed once
        # in 5d8d49401, reintroduced by 8962ce5f7, and again after 4e964ce12.
        #
        # So this is written as a plain loop with a named accumulator: there is
        # no `reduce` for that rule to recognise, and the data-flow is on the
        # page rather than in a method's return-value contract. The rule has
        # also been narrowed, but the code should not depend on that.
        def apply_transforms(src, transforms)
          current = src
          transforms.each do |transform|
            transform_labels = @transforms.dup
            candidate = send(transform, current)

            if ruby? && candidate != current && parses?(current) && !parses?(candidate)
              # Transform turned valid Ruby into unparseable Ruby — a line-heuristic
              # misfire on a multi-line construct. Discard it (and any label it
              # recorded); keep the prior source.
              @transforms.replace(transform_labels)
              next
            end

            current = candidate
          end
          current
        end

        def parses?(src) = !Prism.parse(src).failure?

        def expand_tabs(src)
          return src unless src.include?("\t")

          out = src.gsub("\t", "  ")
          @transforms << :expand_tabs if out != src
          out
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

        def ensure_final_newline(src)
          return src if src.empty? || src.end_with?("\n")

          @transforms << :final_newline
          src + "\n"
        end

        def publish_and_write(out)
          write_back(out)
          @bus&.publish("ast_fixer:transform", path: @path, transforms: @transforms)
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
          delete_temporary_path(temporary_path) if defined?(temporary_path)
          raise e
        end

        def delete_temporary_path(path)
          File.delete(path) if path && File.exist?(path)
        rescue StandardError => e
          Master::Ground::Swallow.log(e, context: "AstFixer.delete_temporary_path")
          nil
        end
      end
    end
  end
end
