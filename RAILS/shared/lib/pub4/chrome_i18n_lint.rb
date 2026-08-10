# frozen_string_literal: true

module Pub4
  # Ratchet: empty-state titles and live-search placeholders must go through
  # I18n (t(...)), not hardcoded English. Default locale is :nb across the
  # family — raw "No …" / "Search …" re-introduces EN chrome on every surface.
  #
  # Mirrors empty_state_lint: baseline 0, never raise to silence new debt.
  # Opt out a deliberate EN-only string with: <%# chrome_i18n: ok %>
  #
  # MASTER playbook: design_rules.yml#ui_polish + surface_rules ERB_HARDCODED_CHROME.
  module ChromeI18nLint
    # title: "No …" / title: "Nothing …" without t(
    EMPTY_TITLE = /
      title:\s*
      (?:
        "(?:No\s|Nothing\s)[^"]{0,80}"
        |
        '(?:No\s|Nothing\s)[^']{0,80}'
      )
    /x

    # placeholder: "Search …" without t(
    SEARCH_PLACEHOLDER = /
      placeholder:\s*
      (?:
        "Search[^"]{0,80}"
        |
        'Search[^']{0,80}'
      )
    /x

    # aria-label="…" / aria: { label: "…" } with a literal string.
    #
    # RAILS/gates/data/GATE_ADEQUACY.md gap 2: "chrome_i18n_lint only empty titles +
    # search placeholders; secondary aria-labels still EN." A screen-reader user on
    # :nb hears English for every one of them, and until this rule existed the number
    # was unknown — which is the actual problem. It is 172 (measured 2026-08-01, all
    # three apps plus the shared engine), so the baseline is 172, not 0: translating
    # them needs Norwegian copy, not a regex, and 172 is the debt this measures rather
    # than pretends away.
    #
    # Same ratchet contract as empty_state_lint, which went 48 → 0 this way.
    ARIA_LABEL = /
      (?:aria-label|aria-roledescription)\s*=\s*"[^"<%]{2,80}"
      |
      aria:\s*\{[^}]*?label:\s*"[^"<%]{2,80}"
    /x

    OPT_OUT = "chrome_i18n: ok"

    # Per kind, because they are not the same debt. A new hardcoded empty title is a
    # regression against a solved problem; an aria-label is one more of 158.
    BASELINES = {
      "empty_title" => 0,
      "search_placeholder" => 0,
      # 172 → 169 → 141 → 135 → 134 (2026-08-04) → 133 → 127 (2026-08-10):
      # bsdports ports/show, then its index, list, categories and maintainers
      # views, five amber views, and tv/home. One of those was not a fix —
      # amber's .compose-fab carried an aria-label and the element was deleted,
      # having been invisible since shared/_shell.scss hid it. The last six are
      # amber's footer, whose column labels were hardcoded English until it
      # gained a language switcher. Down only.
      "aria_label" => 127,
    }.freeze

    # Kept for callers that referenced the old single number.
    BASELINE = 0

    Finding = Struct.new(:file, :line, :kind)

    module_function

    def counts(findings = scan)
      BASELINES.keys.to_h { |kind| [kind, findings.count { |f| f.kind == kind }] }
    end

    def over_baseline(findings = scan)
      counts(findings).filter_map do |kind, count|
        baseline = BASELINES.fetch(kind)
        "#{kind}: #{count} (baseline #{baseline}, +#{count - baseline})" if count > baseline
      end
    end

    def run
      findings = scan
      counts(findings).each do |kind, count|
        baseline = BASELINES.fetch(kind)
        note = count < baseline ? " — under baseline, lower it" : ""
        puts "chrome_i18n_lint: #{kind} #{count} (baseline #{baseline})#{note}"
      end

      exceeded = over_baseline(findings)
      offenders = findings.select { |f| exceeded.any? { |line| line.start_with?("#{f.kind}:") } }
      offenders.first(30).each { |f| puts "  #{f.file}:#{f.line} [#{f.kind}]" }
      puts "  …" if offenders.size > 30

      return true if exceeded.empty?

      warn "chrome_i18n_lint: exceeds baseline — #{exceeded.join("; ")}"
      warn "chrome_i18n_lint: use t(\"empty.*\") / t(\"search.*\") / t(\"a11y.*\") or mark #{OPT_OUT}"
      false
    end

    def rails_root
      File.expand_path("../../..", __dir__)
    end

    # brgen's verticals moved to engines/<name>/app/views, which the single-level
    # glob never matched. The aria_label count fell 169 -> 89 on the extraction and
    # read as an 80-finding improvement; it was the lint going blind to 57 views.
    def view_paths
      Dir.glob(File.join(rails_root, "*/app/views/**/*.erb")) +
        Dir.glob(File.join(rails_root, "*/engines/*/app/views/**/*.erb"))
    end

    def scan
      findings = []
      view_paths.sort.each do |path|
        # Doc comment inside the partial itself is not a call site.
        next if path.end_with?("shared/_empty_state.html.erb")

        lines = File.readlines(path, encoding: "UTF-8")
        lines.each_with_index do |line, i|
          next if line.include?("t(") || line.include?("I18n.t")
          next if comment_or_opt_out?(lines, i)

          if line.match?(EMPTY_TITLE)
            findings << Finding.new(rel(path), i + 1, "empty_title")
          elsif line.match?(SEARCH_PLACEHOLDER)
            findings << Finding.new(rel(path), i + 1, "search_placeholder")
          elsif line.match?(ARIA_LABEL)
            findings << Finding.new(rel(path), i + 1, "aria_label")
          end
        end
      end
      findings
    end

    def rel(path)
      path.sub("#{rails_root}/", "")
    end

    def comment_or_opt_out?(lines, index)
      window = lines[[index - 1, 0].max..index].join
      window.include?(OPT_OUT) || window.lstrip.start_with?("<%#", "#")
    end
  end
end

exit(Pub4::ChromeI18nLint.run ? 0 : 1) if $PROGRAM_NAME == __FILE__
