# frozen_string_literal: true

require_relative "../../tools/scale_lint"
require_relative "visual_groups"
require_relative "../../checks/support/pixel_match"

module Master
  module Fix
    # The visual lane's simplify stage, modelled on Claude Code's /simplify (reuse,
    # simplification, efficiency, altitude) and subtractive by design: it only removes or merges.
    #
    #   reuse     a rule block that repeats another's body becomes one rule for both selectors;
    #             a literal equal to a declared custom property becomes that property
    #   simplify  a bare wrapper div around a single element goes (ANTI_DIVITIS)
    #
    # A change is kept only when a count falls (selectors, distinct values per property, wrapper
    # divs, DOM depth, lines) and the render shows no changed pixel; a lower count with a visible
    # change goes to the independent reviewer, and a count that did not fall is refused.
    module VisualSimplify
      CENSUS = ::Operator::ScaleLint::Census
      RULE = /(?<selectors>[^{}]+)\{(?<body>[^{}]*)\}/
      # A <div> with no attributes holding exactly one element and nothing else.
      WRAPPER = Regexp.new('<div>\s*(?<inner><(?<tag>\w+)\b[^>]*>(?:(?!<\k<tag>\b).)*?</\k<tag>>)\s*</div>',
                           Regexp::MULTILINE)
      TOKEN = /(--[\w-]+)\s*:\s*([^;{}]+);/
      # A property, not a custom property: those are where the tokens are declared.
      DECLARATION = /(?<![\w-])([a-z][\w-]*)\s*:\s*([^;{}]+);/

      module_function

      # Every count the stage may lower, and their sum.
      def counts(html:, css:)
        rows = { selectors: css.scan(RULE).sum { |selectors, _body| selectors.split(",").size },
                 values: CENSUS.counts(css).values.sum, wrappers: html.scan(WRAPPER).size, depth: depth(html),
                 lines: css.lines.count { |line| !line.strip.empty? } }
        rows.merge(total: rows.values.sum)
      end

      def depth(html)
        level = 0
        levels = html.scan(%r{<(/?)\w+[^>]*?(/?)>}).map { |closing, empty| level += step(closing, empty) }
        levels.max.to_i
      end

      def step(closing, empty)
        return -1 unless closing.empty?

        empty.empty? ? 1 : 0
      end

      def reduce(html:, css:) = { html: unwrap(html), css: tokenise(merge_duplicates(css)) }

      def unwrap(html)
        loop do
          reduced = html.gsub(WRAPPER) { Regexp.last_match[:inner] }
          return reduced if reduced == html

          html = reduced
        end
      end

      # Rules whose bodies are the same declarations become one rule, at the first one's place.
      def merge_duplicates(css)
        rules = css.to_enum(:scan, RULE).map { Regexp.last_match }
        repeated = rules.group_by { |rule| declarations(rule[:body]) }.values.select { |same| same.size > 1 }
        repeated.reduce(css) { |text, same| merged(text, same) }
      end

      def merged(text, same)
        joined = same.map { |rule| rule[:selectors].strip }.join(", ")
        text = same.drop(1).reduce(text) { |out, rule| out.sub(rule[0], "") }
        text.sub(same.first[0], "#{joined} {#{same.first[:body]}}")
      end

      def declarations(body) = body.split(";").map { |part| part.strip.squeeze(" ") }.reject(&:empty?).sort

      # A literal written where a custom property declares exactly that value.
      def tokenise(css)
        tokens = css.scan(TOKEN).to_h { |name, value| [value.strip.downcase, name] }
        css.gsub(DECLARATION) do |written|
          prop, value = Regexp.last_match.captures
          name = tokens[value.strip.downcase]
          name ? "#{prop}: var(#{name});" : written
        end
      end

      # :accepted, :review or :refused, from the counts before and after and the changed pixels.
      def verdict(before:, after:, changed_pixels:)
        return :refused unless after[:total] < before[:total]

        changed_pixels.zero? ? :accepted : :review
      end

      # The stage over a tree: RAILS/__shared first (fix it once, not per app), a bounded number of
      # stylesheets a pass, each reduced, measured and kept, reviewed or put back.
      # shots ->(path) { [[before png, after png], ...] after the block wrote the candidate } is the
      # lane's re-render; review ->(group, regions) as VisualLane's.
      class Stage
        SHEETS = Integer(ENV.fetch("MASTER_VISUAL_SIMPLIFY_SHEETS", "4"))
        Change = Data.define(:path, :before, :after)

        def initialize(repo_root:, shots:, review:, commit:)
          @repo_root = repo_root
          @shots = shots
          @review = review
          @commit = commit
        end

        def run(sheets)
          ordered = sheets.sort_by { |path| [path.include?("/__shared/") ? 0 : 1, path] }
          ordered.first(SHEETS).map { |path| sheet(path) }
        end

        def sheet(path)
          before = File.read(path)
          after = VisualSimplify.reduce(html: "", css: before)[:css]
          change = Change.new(path:, before:, after:)
          return :nothing_to_remove if after == before

          pairs = @shots.call(path) { File.write(path, after) }
          settle(change, pairs)
        end

        def settle(change, pairs)
          verdict = VisualSimplify.verdict(before: VisualSimplify.counts(html: "", css: change.before),
                                           after: VisualSimplify.counts(html: "", css: change.after),
                                           changed_pixels: pairs ? changed(pairs) : 1)
          return keep(change) if verdict == :accepted || (verdict == :review && reviewed?(change, pairs))

          File.write(change.path, change.before)
          verdict == :refused ? :no_count_fell : :visible_change_not_approved
        end

        def changed(pairs) = pairs.sum { |pair| compare(pair)[:pixel_diff_count].to_i }

        def compare(pair) = Deploy::PixelMatch.compare(baseline_path: pair[0], current_path: pair[1])

        def reviewed?(change, pairs)
          return false unless pairs&.any?

          file = rel(change.path)
          group = VisualGroups::Group.new(key: "SIMPLIFY | #{file}", id: "simplify", law: "AESTHETIC_MINIMALISM", file:,
                                          members: ["simplify #{file}"], surfaces: [], before: [pairs.first[0]],
                                          after: [pairs.first[1]], fix: :mechanical)
          @review&.call(group, compare(pairs.first)[:regions]) == :approved
        end

        def keep(change)
          @commit.call(change.path)
          :applied
        end

        def rel(path) = path.delete_prefix("#{@repo_root}/")
      end
    end
  end
end
