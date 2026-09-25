# frozen_string_literal: true

module Operator
  # Source-side typography contract. It does not judge taste; it verifies that
  # reading surfaces carry the typographic machinery declared by MASTER.
  class TypographyLint
    Finding = Data.define(:file, :line, :kind, :message)

    PROSE_MARKERS = /(?:^|[ .#>])(?:prose|post[_-]?body|feed-post-(?:body|prose)|article-body|editorial-body|legal-prose|copy|markdown)/i
    PROSE_DECLARATIONS = {
      "measure" => /max-width\s*:\s*(?:var\([^)]*measure|(?:\d+(?:\.\d+)?)ch)/i,
      "leading" => /line-height\s*:\s*(?:var\([^)]*leading|1(?:\.\d+)?)/i,
      "hanging" => /hanging-punctuation\s*:\s*[^;]+;/i,
      "hyphenation" => /(?:-webkit-)?hyphens\s*:\s*auto\s*;/i,
      "text_wrap" => /text-wrap\s*:\s*(?:pretty|balance|stable|wrap|nowrap)\s*;/i,
      "orphans" => /orphans\s*:\s*\d+/i,
      "widows" => /widows\s*:\s*\d+/i,
      "features" => /(?:font-feature-settings|font-kerning|font-variant-[^:]+)\s*:/i,
    }.freeze

    FAMILY_DECLARATIONS = /font-family\s*:\s*([^;]+);/i
    CAPS_DECLARATION = /text-transform\s*:\s*uppercase/i
    VARIABLE_FONT_DECLARATION = /font-weight\s*:\s*\d+\s+\d+/i
    VARIABLE_AXIS_DECLARATION = /font-variation-settings\s*:/i
    OPTICAL_SIZING_DECLARATION = /font-optical-sizing\s*:/i
    TRACKING_DECLARATION = /letter-spacing\s*:/i
    JUSTIFY_DECLARATION = /text-align\s*:\s*justify/i
    NUMERIC_SELECTOR = /(?:price|amount|total|quantity|count|numeric|money|number)/i

    PROFILE_HINTS = {
      "editorial" => { measure: "66ch", leading: 1.5, text_wrap: "pretty", numbers: true },
      "legal" => { measure: "66ch", leading: 1.5, text_wrap: "pretty", numbers: true },
      "social" => { measure: "45–55ch", leading: 1.5, text_wrap: "pretty", numbers: true },
      "terminal" => { measure: "80ch", leading: 1.4, text_wrap: "stable", numbers: false },
      "marketplace" => { measure: "45–66ch", leading: 1.5, text_wrap: "pretty", numbers: true },
    }.freeze

    SOURCES = [
      File.join("brgen", "app", "assets", "stylesheets"),
      File.join("amber", "app", "assets", "stylesheets"),
      File.join("bsdports", "app", "assets", "stylesheets"),
      File.join("shared", "app", "assets", "stylesheets"),
      File.join("MASTER", "web", "public"),
      File.join("MASTER", "web", "src"),
    ].freeze

    def initialize(root:)
      @root = root
    end

    def stylesheets
      SOURCES.flat_map { |dir| Dir.glob(File.join(@root, "RAILS", dir, "**", "*.{css,scss}")) }.uniq.sort
    end

    def findings
      @findings ||= stylesheets.flat_map { |path| inspect_file(path) }
    end

    def counts
      findings.group_by { |finding| finding.kind }.transform_values(&:size)
    end

    def profiles
      PROFILE_HINTS.transform_keys(&:to_s)
    end

    private

    def inspect_file(path)
      source = File.read(path, encoding: "UTF-8")
      lines = source.lines
      result = []

      result.concat(prose_contract(path, lines))
      result.concat(caps_tracking(path, lines))
      result.concat(justification_hyphenation(path, lines))
      result.concat(font_family_budget(path, lines))
      result.concat(numeric_features(path, lines))
      result.concat(variable_font_contract(path, lines))

      result
    rescue StandardError => e
      [Finding.new(relative(path), 1, "unreadable", "typography source unreadable: #{e.class}: #{e.message}")]
    end

    def prose_contract(path, lines)
      return [] unless lines.any? { |line| line.match?(PROSE_MARKERS) }

      joined = lines.join
      missing = PROSE_DECLARATIONS.filter_map do |kind, pattern|
        kind unless joined.match?(pattern)
      end

      missing.map do |kind|
        line = lines.index { |value| value.match?(PROSE_MARKERS) }.to_i + 1
        Finding.new(
          relative(path),
          line,
          "prose_#{kind}",
          "reading surface declares prose intent but has no #{kind} contract",
        )
      end
    end

    def caps_tracking(path, lines)
      return [] unless lines.any? { |line| line.match?(CAPS_DECLARATION) }

      joined = lines.join
      return [] if joined.match?(TRACKING_DECLARATION)

      [Finding.new(
        relative(path),
        lines.index { |line| line.match?(CAPS_DECLARATION) }.to_i + 1,
        "caps_tracking",
        "uppercase text exists without a letter-spacing declaration",
      )]
    end

    def justification_hyphenation(path, lines)
      return [] unless lines.any? { |line| line.match?(JUSTIFY_DECLARATION) }
      return [] if lines.join.match?(/(?:-webkit-)?hyphens\s*:\s*auto/i)

      [Finding.new(
        relative(path),
        lines.index { |line| line.match?(JUSTIFY_DECLARATION) }.to_i + 1,
        "justification_without_hyphenation",
        "justified prose needs hyphenation to prevent excessive word spacing",
      )]
    end

    def font_family_budget(path, lines)
      # Every declaration on the line, not the first: a compact or built sheet
      # puts several rules on one line, and matching once counted one family.
      families = lines.flat_map do |line|
        line.scan(FAMILY_DECLARATIONS).flat_map { |(value)| normalize_family_list(value) }
      end.uniq

      return [] if families.size <= 2

      [Finding.new(
        relative(path),
        1,
        "font_family_budget",
        "#{families.size} font families declared; keep each surface to two functional families unless its profile says otherwise: #{families.join(', ')}",
      )]
    end

    def variable_font_contract(path, lines)
      joined = lines.join
      return [] unless joined.match?(VARIABLE_FONT_DECLARATION) || joined.match?(VARIABLE_AXIS_DECLARATION)
      return [] if joined.match?(OPTICAL_SIZING_DECLARATION)

      [Finding.new(
        relative(path),
        lines.index { |line| line.match?(VARIABLE_FONT_DECLARATION) || line.match?(VARIABLE_AXIS_DECLARATION) }.to_i + 1,
        "optical_sizing",
        "variable font usage should declare font-optical-sizing explicitly so browser optical sizing is a conscious choice",
      )]
    end

    def numeric_features(path, lines)
      return [] unless lines.any? { |line| line.match?(NUMERIC_SELECTOR) }
      return [] if lines.join.match?(/font-variant-numeric|font-feature-settings/i)

      [Finding.new(
        relative(path),
        lines.index { |line| line.match?(NUMERIC_SELECTOR) }.to_i + 1,
        "numeric_features",
        "numeric surface lacks explicit OpenType numeric treatment; use tabular figures for aligned quantities and a deliberate body numeral style for prose",
      )]
    end

    # A var() is a token that names a family elsewhere, and inherit and its kin
    # name none, so neither is a family of its own. Counting them read
    # `var(--font)` as the two families "var" and "font".
    def normalize_family_list(value)
      value.gsub(/var\([^)]*\)/, "").scan(/(?:["'][^"']+["']|[A-Za-z][\w -]*)/).map { |item| item.strip.delete_prefix("'").delete_suffix("'").delete_prefix('"').delete_suffix('"') }.reject do |item|
        item.empty? || %w[serif sans-serif monospace cursive fantasy system-ui ui-sans-serif ui-monospace
                          inherit initial unset revert revert-layer].include?(item.downcase)
      end
    end

    def relative(path)
      path.delete_prefix("#@root/")
    end
  end
end
