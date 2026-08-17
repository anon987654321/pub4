# frozen_string_literal: true

require_relative "../../../../OPENBSD/lib/gate_result"

module Deploy
  # dart-sass's compressed output mode has a real, reproducible bug: a long
  # comma-separated compound-selector list can lose an individual selector's
  # qualifying class during minification (confirmed live on brgen.no --
  # every post avatar rendered as a full-width bar instead of a small circle
  # because ".feed-card.listing .feed-card-avatar, ..." compressed down to a
  # bare ".feed-card-avatar" that then matched every card, not just listings).
  # This gate compiles each app's stylesheet entrypoint in both :expanded and
  # :compressed mode and fails if any selector present in the expanded output
  # is missing from the compressed output -- catching that bug class before
  # it ships, regardless of which SCSS file introduces it next.
  class CssMinifyIntegrityGate
    ROOT = File.expand_path("../../../..", __dir__)
    RAILS_ROOT = File.join(ROOT, "RAILS")
    APPS = %w[brgen amber bsdports].freeze
    MIN_SELECTOR_LIST_SIZE = 3

    def self.run
      new.run
    end

    def run
      result = GateResult.new

      begin
        require "sass-embedded"
      rescue LoadError
        result.inconclusive!("css_minify_integrity: sass-embedded gem unavailable — no stylesheet compiled")
        return result
      end

      APPS.each { |app| check_app(result, app) }
      result
    end

    private

    def check_app(result, app)
      entry = File.join(RAILS_ROOT, app, "app/assets/stylesheets/application.scss")
      return result.inconclusive!("css_minify_integrity: #{app} has no application.scss") unless File.file?(entry)

      # The engine paths are not optional. Rails puts each mounted engine's
      # app/assets on the asset load path, so `rake dartsass:build` compiles;
      # this list is hand-built, and without them brgen's application.scss cannot
      # resolve its vertical imports. The gate did not report "brgen unchecked",
      # it reported a Sass::CompileError — so a path list that had gone stale
      # read as a broken stylesheet, and the minify check it exists to run never
      # executed for brgen at all.
      load_paths = [
        File.join(RAILS_ROOT, "shared", "app/assets/stylesheets"),
        File.join(RAILS_ROOT, app, "app/assets/stylesheets"),
        *Dir.glob(File.join(RAILS_ROOT, app, "engines/*/app/assets/stylesheets")),
      ]

      begin
        expanded = Sass.compile(entry, load_paths: load_paths, style: :expanded).css
        compressed = Sass.compile(entry, load_paths: load_paths, style: :compressed).css
      rescue StandardError => e
        result.fail("css_minify_integrity: #{app} failed to compile (#{e.class}: #{e.message})")
        return
      end

      # Exclude ";" from the captured text too -- statement at-rules like
      # "@layer reset, overrides;" end in a semicolon, not a block, and
      # without this a plain [^{}]+ scan spans straight through them into
      # the next real rule's selector, misreading the at-rule's name list
      # as part of a selector list.
      strip_comments(expanded).scan(/([^{};]+)\{/) do |(selector_text)|
        next unless selector_text.include?(",")
        next if selector_text.lstrip.start_with?("@")

        selectors = selector_text.split(",").map(&:strip).reject(&:empty?)
        next if selectors.length < MIN_SELECTOR_LIST_SIZE

        normalized_compressed = normalize_selector(compressed)
        missing = selectors.reject { |sel| normalized_compressed.include?(normalize_selector(sel)) }
        next if missing.empty?

        result.fail(
          "css_minify_integrity: #{app} lost selector(s) under compression -- " \
          "list started with #{selectors.first.inspect} (#{selectors.length} items), " \
          "missing after compression: #{missing.inspect}"
        )
      end
      # This app's stylesheet was compiled and compared; an app without an
      # application.scss should not make the ones that have it count for nothing.
      result.checked!
    end

    def strip_comments(css)
      css.gsub(%r{/\*.*?\*/}m, "")
    end

    # dart-sass's compressed output strips whitespace immediately around
    # explicit combinators (>, +, ~) but keeps the single space that IS the
    # descendant combinator between simple selectors (e.g. ".a>b c", not
    # ".a>bc"). Normalize both sides the same way instead of stripping all
    # whitespace, which produced false positives on exactly these selectors.
    def normalize_selector(text)
      text.gsub(/\s*([>+~])\s*/, '\1').gsub(/\s+/, " ").strip
    end
  end
end
